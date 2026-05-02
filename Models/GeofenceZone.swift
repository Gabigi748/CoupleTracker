// GeofenceZone.swift
// CoupleTracker
//
// 地理圍欄模型 — 定義監控區域與通知觸發條件
// 後端 geofences 表欄位：id, user_id, name, lat, lng, radius, notify_type, is_active, created_at

import Foundation
import CoreLocation

/// 地理圍欄區域模型
/// 對應後端 geofences 表
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
    
    /// 是否啟用
    var isActive: Bool
    
    /// 建立時間
    let createdAt: Date
    
    // MARK: - 自訂解碼（處理後端 lat/lng + notify_type 格式）
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case lat
        case lng
        case latitude
        case longitude
        case radius
        case notifyType = "notify_type"
        case notifyOnEntry = "notify_on_entry"
        case notifyOnExit = "notify_on_exit"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // id 可能是 Int 或 String
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
        
        name = try container.decode(String.self, forKey: .name)
        
        // 支援 lat/lng 或 latitude/longitude
        if let lat = try? container.decode(Double.self, forKey: .lat) {
            latitude = lat
        } else {
            latitude = try container.decode(Double.self, forKey: .latitude)
        }
        
        if let lng = try? container.decode(Double.self, forKey: .lng) {
            longitude = lng
        } else {
            longitude = try container.decode(Double.self, forKey: .longitude)
        }
        
        radius = try container.decodeIfPresent(Double.self, forKey: .radius) ?? 200
        
        // 支援 notify_type（後端格式）或 notify_on_entry/notify_on_exit
        if let notifyType = try? container.decode(String.self, forKey: .notifyType) {
            switch notifyType {
            case "entry":
                notifyOnEntry = true
                notifyOnExit = false
            case "exit":
                notifyOnEntry = false
                notifyOnExit = true
            default: // "both" 或其他
                notifyOnEntry = true
                notifyOnExit = true
            }
        } else {
            notifyOnEntry = try container.decodeIfPresent(Bool.self, forKey: .notifyOnEntry) ?? true
            notifyOnExit = try container.decodeIfPresent(Bool.self, forKey: .notifyOnExit) ?? true
        }
        
        // is_active：後端可能回傳 0/1 或 true/false
        if let active = try? container.decode(Bool.self, forKey: .isActive) {
            isActive = active
        } else if let activeInt = try? container.decode(Int.self, forKey: .isActive) {
            isActive = activeInt != 0
        } else {
            isActive = true
        }
        
        // created_at：支援 ISO8601 字串或已解碼的 Date
        if let date = try? container.decode(Date.self, forKey: .createdAt) {
            createdAt = date
        } else if let dateStr = try? container.decode(String.self, forKey: .createdAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            createdAt = formatter.date(from: dateStr)
                ?? ISO8601DateFormatter().date(from: dateStr)
                ?? Date()
        } else {
            createdAt = Date()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(latitude, forKey: .lat)
        try container.encode(longitude, forKey: .lng)
        try container.encode(radius, forKey: .radius)
        
        // 編碼為 notify_type 格式（後端格式）
        let notifyType: String
        switch (notifyOnEntry, notifyOnExit) {
        case (true, true): notifyType = "both"
        case (true, false): notifyType = "entry"
        case (false, true): notifyType = "exit"
        case (false, false): notifyType = "both" // 預設 both
        }
        try container.encode(notifyType, forKey: .notifyType)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(createdAt, forKey: .createdAt)
    }
    
    // MARK: - 直接初始化（App 內部使用）
    
    init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        radius: Double,
        notifyOnEntry: Bool,
        notifyOnExit: Bool,
        isActive: Bool = true,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.notifyOnEntry = notifyOnEntry
        self.notifyOnExit = notifyOnExit
        self.isActive = isActive
        self.createdAt = createdAt
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
    
    /// 通知類型字串（供 API 使用）
    var notifyType: String {
        switch (notifyOnEntry, notifyOnExit) {
        case (true, true): return "both"
        case (true, false): return "entry"
        case (false, true): return "exit"
        case (false, false): return "both"
        }
    }
    
    /// Core Location 最多支援 20 個地理圍欄
    static let maxGeofences = 20
}
