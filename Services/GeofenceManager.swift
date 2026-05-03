// GeofenceManager.swift
// CoupleTracker
//
// 地理圍欄管理器 — CRUD 圍欄區域，與 LocationManager 協作監控
// 已移除 Firebase 依賴，改用 APIService 呼叫自建後端

import Foundation
import CoreLocation
import Observation

/// 地理圍欄管理器
/// 負責圍欄的 CRUD 操作，並與 LocationManager 協作進行實際監控
@MainActor
@Observable
final class GeofenceManager {
    
    // MARK: - 屬性
    
    /// 所有圍欄區域列表
    var zones: [GeofenceZone] = []
    
    /// 是否正在載入
    var isLoading: Bool = false
    
    /// 錯誤訊息
    var errorMessage: String?
    
    // MARK: - 私有屬性
    
    /// 位置管理器（用於實際監控圍欄）
    private let locationManager: LocationManager
    
    /// API 服務參考
    private weak var apiService: APIService?
    
    // MARK: - 初始化
    
    /// 初始化圍欄管理器
    /// - Parameter locationManager: 位置管理器實例
    init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }
    
    /// 設定 API 服務參考
    /// - Parameter apiService: APIService 實例
    func configure(with apiService: APIService) {
        self.apiService = apiService
    }
    
    // MARK: - CRUD 操作
    
    /// 從後端載入所有圍欄區域
    func loadZones() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let apiService else {
                print("[Geofence] loadZones: apiService 為 nil，無法載入")
                return
            }
            zones = try await apiService.getGeofences()
            print("[Geofence] loadZones: 載入了 \(zones.count) 個圍欄: \(zones.map { "\($0.id):\($0.name)" })")
            // 同步監控狀態
            await syncMonitoredRegions()
        } catch {
            errorMessage = "載入圍欄失敗：\(error.localizedDescription)"
            print("[Geofence] loadZones 失敗: \(error)")
        }
    }
    
    /// 新增圍欄區域
    /// - Parameter zone: 要新增的圍欄
    func addZone(_ zone: GeofenceZone) async throws {
        // 檢查數量限制
        guard zones.count < GeofenceZone.maxGeofences else {
            throw CoupleTrackerError.geofenceLimitReached
        }
        
        guard let apiService else { return }
        
        // 呼叫 API 新增
        let created = try await apiService.createGeofence(zone)
        zones.append(created)
        
        // 開始監控
        _ = locationManager.startMonitoring(zone: created)
    }
    
    /// 更新圍欄區域
    /// - Parameter zone: 更新後的圍欄
    func updateZone(_ zone: GeofenceZone) async throws {
        guard let apiService else { return }
        
        // 先停止舊的監控
        locationManager.stopMonitoring(zone: zone)
        
        // 呼叫 API 更新
        try await apiService.updateGeofence(zone)
        
        // 更新本地列表
        if let index = zones.firstIndex(where: { $0.id == zone.id }) {
            zones[index] = zone
        }
        
        // 重新開始監控
        _ = locationManager.startMonitoring(zone: zone)
    }
    
    /// 刪除圍欄區域
    /// - Parameter zone: 要刪除的圍欄
    func deleteZone(_ zone: GeofenceZone) async throws {
        guard let apiService else { return }
        
        // 停止監控
        locationManager.stopMonitoring(zone: zone)
        
        // 呼叫 API 刪除
        try await apiService.deleteGeofence(zone.id)
        
        // 從本地列表移除
        zones.removeAll { $0.id == zone.id }
    }
    
    /// 刪除所有圍欄
    func deleteAllZones() async throws {
        guard let apiService else { return }
        
        // 停止所有監控
        locationManager.stopAllMonitoring()
        
        // 逐一刪除（後端可能沒有批次刪除 API）
        for zone in zones {
            try await apiService.deleteGeofence(zone.id)
        }
        
        zones.removeAll()
    }
    
    // MARK: - 監控同步
    
    /// 同步 Core Location 監控的圍欄與後端的圍欄列表
    private func syncMonitoredRegions() async {
        // 先停止所有監控
        locationManager.stopAllMonitoring()
        
        // 重新監控所有圍欄
        for zone in zones {
            let success = locationManager.startMonitoring(zone: zone)
            print("[Geofence] 註冊監控圍欄 \(zone.id):\(zone.name) (lat:\(zone.latitude), lng:\(zone.longitude), r:\(zone.radius)m) → \(success ? "成功" : "失敗")")
        }
        print("[Geofence] 目前監控中的圍欄數: \(locationManager.monitoredRegionsCount)")
    }
    
    // MARK: - 查詢
    
    /// 根據 ID 查找圍欄
    /// - Parameter id: 圍欄 ID
    /// - Returns: 對應的圍欄區域
    func zone(by id: String) -> GeofenceZone? {
        zones.first { $0.id == id }
    }
    
    /// 取得剩餘可用圍欄數量
    var remainingSlots: Int {
        max(0, GeofenceZone.maxGeofences - zones.count)
    }
    
    // MARK: - 軟體圍欄檢查（補充 iOS 系統圍欄的不足）
    
    /// 每個圍欄的上次狀態（true = 在圍欄內）
    private var zoneInsideState: [String: Bool] = [:]
    
    /// 根據當前位置手動檢查所有圍欄的進出狀態
    /// 每次位置更新時呼叫，比 iOS 系統圍欄更即時
    /// - Parameter location: 當前位置
    /// - Returns: 觸發的圍欄事件列表
    func checkGeofences(location: CLLocation) -> [GeofenceEvent] {
        var events: [GeofenceEvent] = []
        
        for zone in zones {
            let center = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
            let distance = location.distance(from: center)
            let isInside = distance <= zone.radius
            let wasInside = zoneInsideState[zone.id] ?? false
            
            if isInside && !wasInside && zone.notifyOnEntry {
                // 進入圍欄
                events.append(GeofenceEvent(regionId: zone.id, type: .entry, timestamp: Date()))
                print("[Geofence-Soft] 進入圍欄 \(zone.name) (距離: \(Int(distance))m, 半徑: \(Int(zone.radius))m)")
            } else if !isInside && wasInside && zone.notifyOnExit {
                // 離開圍欄
                events.append(GeofenceEvent(regionId: zone.id, type: .exit, timestamp: Date()))
                print("[Geofence-Soft] 離開圍欄 \(zone.name) (距離: \(Int(distance))m, 半徑: \(Int(zone.radius))m)")
            }
            
            zoneInsideState[zone.id] = isInside
        }
        
        return events
    }
    
    /// 初始化圍欄狀態（載入圍欄後呼叫，避免首次位置更新誤觸發）
    func initializeStates(currentLocation: CLLocation?) {
        guard let location = currentLocation else { return }
        for zone in zones {
            let center = CLLocation(latitude: zone.latitude, longitude: zone.longitude)
            let distance = location.distance(from: center)
            zoneInsideState[zone.id] = distance <= zone.radius
        }
        print("[Geofence-Soft] 初始化狀態: \(zoneInsideState.map { "\($0.key)=\($0.value ? "內" : "外")" })")
    }
}
