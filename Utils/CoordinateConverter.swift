// CoordinateConverter.swift
// CoupleTracker
//
// GCJ-02 座標偏移修正工具
// 處理 WGS-84 與 GCJ-02（中國國測局座標系）之間的轉換
// 用於解決中國大陸 MapKit（高德地圖）與國際 Apple Maps 之間的座標偏移問題

import Foundation

/// 座標轉換工具
/// 提供 WGS-84 ↔ GCJ-02 座標系轉換
enum CoordinateConverter {
    
    // MARK: - 常數
    
    /// 長半軸（GRS 80 / WGS-84 橢球體）
    private static let a: Double = 6378245.0
    
    /// 第一偏心率平方
    private static let ee: Double = 0.00669342162296594323
    
    /// π
    private static let pi = Double.pi
    
    // MARK: - 公開方法
    
    /// 判斷座標是否在中國境內（粗略矩形範圍）
    /// - Parameters:
    ///   - lat: 緯度（WGS-84）
    ///   - lng: 經度（WGS-84）
    /// - Returns: 是否在中國境內
    static func isInsideChina(lat: Double, lng: Double) -> Bool {
        // 中國大陸大致範圍（排除台灣、港澳不需要排除因為也用 GCJ-02）
        // 基本範圍檢查
        guard lng >= 72.004 && lng <= 137.8347 && lat >= 0.8293 && lat <= 55.8271 else {
            return false
        }
        // 排除台灣（緯度 21.5~26, 經度 119.5~122.5）
        if lat >= 21.5 && lat <= 26.0 && lng >= 119.5 && lng <= 122.5 {
            return false
        }
        return true
    }
    
    /// WGS-84 座標轉 GCJ-02 座標
    /// - Parameters:
    ///   - lat: WGS-84 緯度
    ///   - lng: WGS-84 經度
    /// - Returns: GCJ-02 座標 (lat, lng)
    static func wgs84ToGcj02(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        // 不在中國境內，不做轉換
        guard isInsideChina(lat: lat, lng: lng) else {
            return (lat, lng)
        }
        
        var dLat = transformLat(x: lng - 105.0, y: lat - 35.0)
        var dLng = transformLng(x: lng - 105.0, y: lat - 35.0)
        
        let radLat = lat / 180.0 * pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * pi)
        dLng = (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * pi)
        
        let mgLat = lat + dLat
        let mgLng = lng + dLng
        
        return (mgLat, mgLng)
    }
    
    /// GCJ-02 座標轉 WGS-84 座標（逆向轉換，迭代法）
    /// - Parameters:
    ///   - lat: GCJ-02 緯度
    ///   - lng: GCJ-02 經度
    /// - Returns: WGS-84 座標 (lat, lng)
    static func gcj02ToWgs84(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        // 不在中國境內，不做轉換
        guard isInsideChina(lat: lat, lng: lng) else {
            return (lat, lng)
        }
        
        // 迭代法：精度更高（誤差 < 0.5m）
        var wgsLat = lat
        var wgsLng = lng
        
        for _ in 0..<10 {
            let gcj = wgs84ToGcj02(lat: wgsLat, lng: wgsLng)
            wgsLat += lat - gcj.lat
            wgsLng += lng - gcj.lng
            
            // 收斂判斷
            if abs(lat - gcj.lat) < 1e-9 && abs(lng - gcj.lng) < 1e-9 {
                break
            }
        }
        
        return (wgsLat, wgsLng)
    }
    
    // MARK: - 判斷設備是否在中國地區
    
    /// 判斷設備是否在中國地區
    /// MapKit 用哪套底圖（高德 GCJ-02 vs Apple Maps WGS-84）取決於設備的
    /// App Store 地區設定，不是 GPS 物理位置。台灣機即使人在中國，MapKit
    /// 底圖仍是 WGS-84，不需要做 GCJ-02 轉換。
    static var isDeviceInChina: Bool {
        // 只看系統地區設定（對應 App Store country/region）
        if let regionCode = Locale.current.region?.identifier, regionCode == "CN" {
            return true
        }
        return false
    }
    
    /// 最後已知的 GPS 座標（由 LocationManager 更新）
    nonisolated(unsafe) static var lastKnownCoordinate: (lat: Double, lng: Double)?
    
    // MARK: - 私有方法
    
    /// 緯度偏移轉換函數
    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * pi) + 320.0 * sin(y * pi / 30.0)) * 2.0 / 3.0
        return ret
    }
    
    /// 經度偏移轉換函數
    private static func transformLng(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0
        return ret
    }
}
