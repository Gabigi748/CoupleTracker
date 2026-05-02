// LocationHistoryPoint.swift
// CoupleTracker
//
// 位置歷史點模型 — 對應後端 GET /api/locations/history 回傳的資料格式
// 後端 locations 表欄位：id, user_id, lat, lng, accuracy, battery, created_at

import Foundation
import CoreLocation

/// 位置歷史點模型
/// 對應後端 locations 表的單筆記錄
struct LocationHistoryPoint: Codable, Identifiable, Sendable {
    /// 資料庫主鍵
    let id: Int
    
    /// 用戶 ID
    let userId: Int
    
    /// 緯度（WGS-84）
    let lat: Double
    
    /// 經度（WGS-84）
    let lng: Double
    
    /// 定位精度（公尺）
    let accuracy: Double?
    
    /// 電量百分比（0-100）
    let battery: Int?
    
    /// 記錄時間（ISO 8601 字串）
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case lat, lng, accuracy, battery
        case createdAt = "created_at"
    }
}

// MARK: - 便利方法

extension LocationHistoryPoint {
    /// 轉換為 CLLocationCoordinate2D（供 MapKit 使用）
    /// 如果設備在中國，自動套用 GCJ-02 座標偏移修正
    var coordinate: CLLocationCoordinate2D {
        if CoordinateConverter.isDeviceInChina {
            let converted = CoordinateConverter.wgs84ToGcj02(lat: lat, lng: lng)
            return CLLocationCoordinate2D(latitude: converted.lat, longitude: converted.lng)
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    
    /// 解析 createdAt 為 Date
    var date: Date {
        // 嘗試帶毫秒的 ISO 8601 格式
        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractional.date(from: createdAt) {
            return date
        }
        // 退回標準 ISO 8601
        if let date = ISO8601DateFormatter().date(from: createdAt) {
            return date
        }
        return Date()
    }
    
    /// 轉換為 CLLocation（供反向地理編碼使用）
    var clLocation: CLLocation {
        CLLocation(latitude: lat, longitude: lng)
    }
}
