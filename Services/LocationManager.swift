// LocationManager.swift
// CoupleTracker
//
// Core Location 管理器 — 處理定位權限、背景/前景定位、地理圍欄監控
// 改善：distanceFilter 降至 5m、過濾精度 > 100m 的位置

import Foundation
import CoreLocation
import UIKit
import Observation
import UserNotifications

/// 定位管理器
/// 負責所有 Core Location 相關操作：權限請求、位置更新、地理圍欄
@MainActor
@Observable
final class LocationManager: NSObject {
    
    // MARK: - 屬性
    
    /// 當前位置
    var currentLocation: Location?
    
    /// 當前定位精度（公尺）
    var currentAccuracy: Double?
    
    /// 授權狀態
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    /// 是否正在更新位置
    var isUpdatingLocation: Bool = false
    
    /// 最近的定位錯誤
    var locationError: String?
    
    /// 目前監控中的圍欄數量
    var monitoredRegionsCount: Int = 0
    
    /// 圍欄事件回調
    var onGeofenceEvent: ((GeofenceEvent) -> Void)?
    
    /// 位置更新回調
    var onLocationUpdate: ((Location) -> Void)?
    
    // MARK: - 私有屬性
    
    /// Core Location 管理器
    private let locationManager = CLLocationManager()
    
    /// 精度過濾閾值（公尺）— 超過此值的位置更新會被丟棄
    private let maxAcceptableAccuracy: CLLocationDistance = 100
    
    // MARK: - 初始化
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        // 背景定位設定
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
        // 距離過濾器：移動 5 公尺就觸發更新（從 10m 降低以提高精度）
        locationManager.distanceFilter = 5
        // 啟用活動類型提示，讓系統更好地優化定位
        locationManager.activityType = .other
        
        authorizationStatus = locationManager.authorizationStatus
    }
    
    // MARK: - 權限請求
    
    /// 請求「永遠允許」定位權限
    /// 注意：iOS 會先給「使用期間」，之後才能升級到「永遠」
    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }
    
    /// 請求「使用期間」定位權限
    func requestWhenInUseAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - 位置更新
    
    /// 開始前景精確定位
    func startUpdatingLocation() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
        locationManager.startUpdatingLocation()
        isUpdatingLocation = true
    }
    
    /// 停止前景定位
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
        isUpdatingLocation = false
    }
    
    /// 切換到前景高精度模式
    func setForegroundAccuracy() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5
    }
    
    /// 切換到背景省電模式（降低精度但保持更新）
    func setBackgroundAccuracy() {
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 20
    }
    
    /// 根據移動狀態智慧調整定位精度
    /// - Parameter activity: 當前移動狀態
    func adjustAccuracyForActivity(_ activity: MotionActivity) {
        switch activity {
        case .stationary:
            // 靜止：低精度省電
            locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            locationManager.distanceFilter = 50
        case .walking, .running:
            // 走路/跑步：高精度
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter = 10
        case .driving:
            // 開車：導航級精度
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.distanceFilter = 20
        case .cycling:
            // 騎車：高精度
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter = 15
        case .unknown:
            // 未知：使用預設
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter = 10
        }
    }
    
    /// 開始背景定位（使用 significant location changes 省電）
    /// 只在位置有顯著變化時才會喚醒 App（通常 500m+）
    func startSignificantLocationMonitoring() {
        locationManager.startMonitoringSignificantLocationChanges()
    }
    
    /// 停止背景定位
    func stopSignificantLocationMonitoring() {
        locationManager.stopMonitoringSignificantLocationChanges()
    }
    
    /// 請求單次位置更新
    func requestOneTimeLocation() {
        locationManager.requestLocation()
    }
    
    // MARK: - 地理圍欄
    
    /// 開始監控一個地理圍欄區域
    /// - Parameter zone: 要監控的圍欄區域
    /// - Returns: 是否成功開始監控
    @discardableResult
    func startMonitoring(zone: GeofenceZone) -> Bool {
        // 檢查是否超過最大數量限制（iOS 最多 20 個）
        guard locationManager.monitoredRegions.count < GeofenceZone.maxGeofences else {
            locationError = "已達到最大圍欄數量限制（\(GeofenceZone.maxGeofences) 個）"
            return false
        }
        
        // 檢查裝置是否支援圍欄監控
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            locationError = "此裝置不支援地理圍欄監控"
            return false
        }
        
        let region = zone.circularRegion
        locationManager.startMonitoring(for: region)
        monitoredRegionsCount = locationManager.monitoredRegions.count
        return true
    }
    
    /// 停止監控一個地理圍欄區域
    /// - Parameter zone: 要停止監控的圍欄區域
    func stopMonitoring(zone: GeofenceZone) {
        let region = zone.circularRegion
        locationManager.stopMonitoring(for: region)
        monitoredRegionsCount = locationManager.monitoredRegions.count
    }
    
    /// 停止所有圍欄監控
    func stopAllMonitoring() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        monitoredRegionsCount = 0
    }
    
    // MARK: - 反向地理編碼
    
    /// 將座標轉換為地址字串
    /// - Parameter location: CLLocation 物件
    /// - Returns: 地址字串
    func reverseGeocode(location: CLLocation) async -> String? {
        do {
            let geocoder = CLGeocoder()
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            
            // 組合地址
            var components: [String] = []
            if let city = placemark.locality { components.append(city) }
            if let district = placemark.subLocality { components.append(district) }
            if let street = placemark.thoroughfare { components.append(street) }
            if let number = placemark.subThoroughfare { components.append(number) }
            
            return components.isEmpty ? nil : components.joined(separator: "")
        } catch {
            return nil
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    
    /// 授權狀態變更
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            authorizationStatus = status
            
            switch status {
            case .authorizedAlways:
                // 已取得「永遠允許」，可以啟動背景定位
                startSignificantLocationMonitoring()
            case .authorizedWhenInUse:
                // 只有「使用期間」，嘗試升級
                locationManager.requestAlwaysAuthorization()
            case .denied, .restricted:
                locationError = "定位權限被拒絕，請到設定中開啟"
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
    
    /// 收到位置更新
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let clLocation = locations.last else { return }
        
        let accuracy = clLocation.horizontalAccuracy
        let location = Location.from(clLocation: clLocation)
        
        // 背景任務保護：確保位置更新能完成發送（即使 App 在背景）
        // 使用 MainActor 同步啟動背景任務，避免 Swift 6 data race
        Task { @MainActor in
            var bgTask: UIBackgroundTaskIdentifier = .invalid
            bgTask = UIApplication.shared.beginBackgroundTask {
                UIApplication.shared.endBackgroundTask(bgTask)
            }
            
            // 更新精度顯示（即使精度差也要顯示）
            currentAccuracy = accuracy
            
            // 過濾精度太差的位置（> 100m 或負值表示無效）
            guard accuracy >= 0 && accuracy <= maxAcceptableAccuracy else {
                print("⚠️ 位置精度太差（\(Int(accuracy))m），已忽略")
                UIApplication.shared.endBackgroundTask(bgTask)
                return
            }
            
            currentLocation = location
            
            // 更新 CoordinateConverter 的最後已知座標（用於判斷是否在中國）
            CoordinateConverter.lastKnownCoordinate = (lat: location.latitude, lng: location.longitude)
            
            onLocationUpdate?(location)
            
            // 給 WebSocket 發送一點時間，然後結束背景任務
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                UIApplication.shared.endBackgroundTask(bgTask)
            }
        }
    }
    
    /// 定位失敗
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            locationError = message
        }
    }
    
    /// 進入地理圍欄
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        print("[Geofence] didEnterRegion: \(circularRegion.identifier)")
        
        // Debug: 發送本地通知確認圍欄觸發
        sendDebugNotification(title: "圍欄觸發", body: "進入圍欄: \(circularRegion.identifier)")
        
        let event = GeofenceEvent(
            regionId: circularRegion.identifier,
            type: .entry,
            timestamp: Date()
        )
        Task { @MainActor in
            onGeofenceEvent?(event)
        }
    }
    
    /// 離開地理圍欄
    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        print("[Geofence] didExitRegion: \(circularRegion.identifier)")
        
        // Debug: 發送本地通知確認圍欄觸發
        sendDebugNotification(title: "圍欄觸發", body: "離開圍欄: \(circularRegion.identifier)")
        
        let event = GeofenceEvent(
            regionId: circularRegion.identifier,
            type: .exit,
            timestamp: Date()
        )
        Task { @MainActor in
            onGeofenceEvent?(event)
        }
    }
    
    /// 圍欄監控失敗
    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let message = "圍欄監控失敗：\(error.localizedDescription)"
        print("[Geofence] monitoringDidFail: \(region?.identifier ?? "nil") - \(error)")
        sendDebugNotification(title: "圍欄監控失敗", body: "\(region?.identifier ?? "?") - \(error.localizedDescription)")
        Task { @MainActor in
            locationError = message
        }
    }
    
    // MARK: - Debug Helper
    
    /// 發送 debug 本地通知（用於確認圍欄是否觸發）
    nonisolated private func sendDebugNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - 圍欄事件

/// 地理圍欄事件
struct GeofenceEvent: Sendable {
    /// 觸發的圍欄 ID
    let regionId: String
    /// 事件類型
    let type: EventType
    /// 觸發時間
    let timestamp: Date
    
    /// 圍欄事件類型
    enum EventType: Sendable {
        case entry  // 進入
        case exit   // 離開
    }
}
