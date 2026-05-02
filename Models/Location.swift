// Location.swift
// CoupleTracker
//
// 位置模型 — 儲存經緯度、時間戳、精度與地址資訊

import Foundation
import CoreLocation

/// 位置模型
/// 對應後端 locations 表
struct Location: Codable, Identifiable, Sendable {
    /// 唯一識別碼（UUID 字串）
    var id: String = UUID().uuidString
    
    /// 緯度
    let latitude: Double
    
    /// 經度
    let longitude: Double
    
    /// 記錄時間
    let timestamp: Date
    
    /// 定位精度（公尺），越小越精確
    var accuracy: Double?
    
    /// 反向地理編碼地址（可選）
    var address: String?
    
    /// 欄位對應
    enum CodingKeys: String, CodingKey {
        case id
        case latitude
        case longitude
        case timestamp
        case accuracy
        case address
    }
}

// MARK: - 便利方法

extension Location {
    /// 從 CLLocation 建立 Location 實例（保留精度資訊）
    static func from(clLocation: CLLocation, address: String? = nil) -> Location {
        Location(
            latitude: clLocation.coordinate.latitude,
            longitude: clLocation.coordinate.longitude,
            timestamp: clLocation.timestamp,
            accuracy: clLocation.horizontalAccuracy,
            address: address
        )
    }
    
    /// 轉換為 CLLocationCoordinate2D（供 MapKit 使用）
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    /// 轉換為 CLLocation
    var clLocation: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
    
    /// 計算與另一個位置的距離（公尺）
    func distance(to other: Location) -> CLLocationDistance {
        clLocation.distance(from: other.clLocation)
    }
    
    /// 精度是否可接受（< 100m）
    var hasAcceptableAccuracy: Bool {
        guard let accuracy else { return true }
        return accuracy > 0 && accuracy <= 100
    }
}
