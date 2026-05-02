// GeofenceZone.swift
// CoupleTracker
//
// 地理圍欄模型 — 定義監控區域與通知觸發條件

import Foundation
import CoreLocation

/// 地理圍欄區域模型
/// 對應 Firestore 中 `users/{uid}/geofences/{id}` 文件
struct GeofenceZone: Codable, Identifiable, Sendable {
    /// 圍欄唯一識別碼
    let id: String
    
    /// 圍欄名稱（例如：「家」、「公司」）
    var name: String
    
    /// 中心點緯度
    let latitude: Double
    
    /// 中心點經度
    let longitude: Double
    
    /// 圍欄半徑（公尺），建議 100-500m
    var radius: Double
    
    /// 進入圍欄時是否通知
    var notifyOnEntry: Bool
    
    /// 離開圍欄時是否通知
    var notifyOnExit: Bool
    
    /// 建立時間
    let createdAt: Date
    
    /// Firestore 欄位對應
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case latitude
        case longitude
        case radius
        case notifyOnEntry = "notify_on_entry"
        case notifyOnExit = "notify_on_exit"
        case createdAt = "created_at"
    }
}

// MARK: - 便利方法

extension GeofenceZone {
    /// 轉換為 CLLocationCoordinate2D
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    /// 轉換為 CLCircularRegion（供 Core Location 監控使用）
    var circularRegion: CLCircularRegion {
        let region = CLCircularRegion(
            center: coordinate,
            radius: radius,
            identifier: id
        )
        region.notifyOnEntry = notifyOnEntry
        region.notifyOnExit = notifyOnExit
        return region
    }
    
    /// 建立新圍欄的便利方法
    static func create(
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double = 200,
        notifyOnEntry: Bool = true,
        notifyOnExit: Bool = true
    ) -> GeofenceZone {
        GeofenceZone(
            id: UUID().uuidString,
            name: name,
            latitude: latitude,
            longitude: longitude,
            radius: radius,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit,
            createdAt: Date()
        )
    }
    
    /// Core Location 最多支援 20 個地理圍欄
    static let maxGeofences = 20
}
