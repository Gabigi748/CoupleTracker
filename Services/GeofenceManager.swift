// GeofenceManager.swift
// CoupleTracker
//
// 地理圍欄管理器 — CRUD 圍欄區域，與 LocationManager 協作監控

import Foundation
import Observation
import FirebaseFirestore

/// 地理圍欄管理器
/// 負責圍欄的 CRUD 操作，並與 LocationManager 協作進行實際監控
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
    
    /// Firestore 資料庫參考
    private let db = Firestore.firestore()
    
    /// 位置管理器（用於實際監控圍欄）
    private let locationManager: LocationManager
    
    /// 圍欄列表監聽器
    private var zonesListener: ListenerRegistration?
    
    // MARK: - 初始化
    
    /// 初始化圍欄管理器
    /// - Parameter locationManager: 位置管理器實例
    init(locationManager: LocationManager) {
        self.locationManager = locationManager
    }
    
    deinit {
        zonesListener?.remove()
    }
    
    // MARK: - CRUD 操作
    
    /// 載入用戶的所有圍欄區域
    /// - Parameter uid: 用戶 UID
    func loadZones(for uid: String) {
        zonesListener?.remove()
        
        zonesListener = db.collection("users").document(uid)
            .collection("geofences")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else {
                    self?.errorMessage = error?.localizedDescription
                    return
                }
                
                let loadedZones = snapshot.documents.compactMap { doc in
                    try? doc.data(as: GeofenceZone.self)
                }
                
                Task { @MainActor in
                    self.zones = loadedZones
                    // 重新同步監控狀態
                    await self.syncMonitoredRegions()
                }
            }
    }
    
    /// 新增圍欄區域
    /// - Parameters:
    ///   - uid: 用戶 UID
    ///   - zone: 要新增的圍欄
    func addZone(for uid: String, zone: GeofenceZone) async throws {
        // 檢查數量限制
        guard zones.count < GeofenceZone.maxGeofences else {
            throw CoupleTrackerError.geofenceLimitReached
        }
        
        // 寫入 Firestore
        try await db.collection("users").document(uid)
            .collection("geofences")
            .document(zone.id)
            .setData(from: zone)
        
        // 開始監控
        _ = await locationManager.startMonitoring(zone: zone)
    }
    
    /// 更新圍欄區域
    /// - Parameters:
    ///   - uid: 用戶 UID
    ///   - zone: 更新後的圍欄
    func updateZone(for uid: String, zone: GeofenceZone) async throws {
        // 先停止舊的監控
        await locationManager.stopMonitoring(zone: zone)
        
        // 更新 Firestore
        try await db.collection("users").document(uid)
            .collection("geofences")
            .document(zone.id)
            .setData(from: zone)
        
        // 重新開始監控
        _ = await locationManager.startMonitoring(zone: zone)
    }
    
    /// 刪除圍欄區域
    /// - Parameters:
    ///   - uid: 用戶 UID
    ///   - zone: 要刪除的圍欄
    func deleteZone(for uid: String, zone: GeofenceZone) async throws {
        // 停止監控
        await locationManager.stopMonitoring(zone: zone)
        
        // 從 Firestore 刪除
        try await db.collection("users").document(uid)
            .collection("geofences")
            .document(zone.id)
            .delete()
    }
    
    /// 刪除所有圍欄
    /// - Parameter uid: 用戶 UID
    func deleteAllZones(for uid: String) async throws {
        // 停止所有監控
        await locationManager.stopAllMonitoring()
        
        // 批次刪除 Firestore 文件
        let batch = db.batch()
        for zone in zones {
            let ref = db.collection("users").document(uid)
                .collection("geofences")
                .document(zone.id)
            batch.deleteDocument(ref)
        }
        try await batch.commit()
    }
    
    // MARK: - 監控同步
    
    /// 同步 Core Location 監控的圍欄與 Firestore 中的圍欄列表
    /// 確保兩邊一致
    private func syncMonitoredRegions() async {
        // 先停止所有監控
        await locationManager.stopAllMonitoring()
        
        // 重新監控所有圍欄
        for zone in zones {
            _ = await locationManager.startMonitoring(zone: zone)
        }
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
}
