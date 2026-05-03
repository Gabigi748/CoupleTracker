// CoupleTrackerAttributes.swift
// CoupleTrackerWidget
//
// Widget Extension 用的 ActivityAttributes 定義（與主 App 的 Models/ 裡相同）
// Widget Extension 是獨立 target，需要自己的副本

import ActivityKit
import Foundation

struct CoupleTrackerAttributes: ActivityAttributes {
    
    public struct ContentState: Codable, Hashable {
        var partnerName: String
        var partnerDistance: Double
        var partnerBattery: Int
        var partnerActivity: String
        var lastUpdateTime: Date
        var stationarySince: Date?
        
        enum CodingKeys: String, CodingKey {
            case partnerName
            case partnerDistance
            case partnerBattery
            case partnerActivity
            case lastUpdateTime
            case stationarySince
        }
    }
    
    var myName: String
}
