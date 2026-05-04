// CoupleTrackerAttributes.swift
// CoupleTracker
//
// Live Activity 資料模型（ActivityAttributes）
// 定義靈動島 + 鎖屏即時資訊的靜態/動態資料

import ActivityKit
import Foundation

/// Live Activity 的資料模型
/// - 靜態資料（建立時設定，不會變）：myName
/// - 動態資料（ContentState，會即時更新）：對方的名字、距離、電量、移動狀態、最後更新時間
struct CoupleTrackerAttributes: ActivityAttributes {
    
    /// 動態資料（會即時更新）
    public struct ContentState: Codable, Hashable {
        /// 對方名字
        var partnerName: String
        /// 對方距離（公尺）
        var partnerDistance: Double
        /// 對方電量（0-100）
        var partnerBattery: Int
        /// 對方移動狀態（"walking", "driving", "stationary" 等）
        var partnerActivity: String
        /// 對方是否在充電
        var partnerCharging: Bool
        /// 最後更新時間
        var lastUpdateTime: Date
        /// 開始靜止的時間（用於判斷是否超過 3 小時顯示睡覺貓）
        var stationarySince: Date?
        
        enum CodingKeys: String, CodingKey {
            case partnerName
            case partnerDistance
            case partnerBattery
            case partnerActivity
            case partnerCharging
            case lastUpdateTime
            case stationarySince
        }
    }
    
    /// 自己的名字（靜態，建立時設定）
    var myName: String
}
