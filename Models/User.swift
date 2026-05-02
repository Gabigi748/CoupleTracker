// User.swift
// CoupleTracker
//
// 用戶模型 — 儲存用戶基本資料、配對狀態、電量與最後位置

import Foundation

/// 用戶模型
/// 對應後端 users 表
struct AppUser: Codable, Identifiable, Sendable {
    /// 用戶唯一識別碼
    var id: String { uid }
    
    /// 用戶 UID
    let uid: String
    
    /// 用戶顯示名稱
    var name: String
    
    /// 用戶 Email
    var email: String
    
    /// 配對對象的 UID（nil 表示尚未配對）
    var partnerUid: String?
    
    /// 配對碼（6 位數字，用於邀請配對）
    var pairingCode: String?
    
    /// 裝置電量百分比（0-100）
    var batteryLevel: Int?
    
    /// 最後已知位置
    var location: Location?
    
    /// 最後更新時間
    var lastUpdated: Date?
    
    /// Firestore 欄位對應
    enum CodingKeys: String, CodingKey {
        case uid
        case name
        case email
        case partnerUid = "partner_uid"
        case pairingCode = "pairing_code"
        case batteryLevel = "battery_level"
        case location
        case lastUpdated = "last_updated"
    }
}

// MARK: - 便利初始化

extension AppUser {
    /// 建立新用戶（註冊時使用）
    static func newUser(uid: String, name: String, email: String) -> AppUser {
        AppUser(
            uid: uid,
            name: name,
            email: email,
            partnerUid: nil,
            pairingCode: nil,
            batteryLevel: nil,
            location: nil,
            lastUpdated: Date()
        )
    }
    
    /// 是否已配對
    var isPaired: Bool {
        partnerUid != nil
    }
}
