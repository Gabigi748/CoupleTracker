// ChatMessage.swift
// CoupleTracker
//
// 聊天訊息模型 — 情侶間的即時訊息
// 後端 messages 表欄位：id, sender_id, receiver_id, text, created_at

import Foundation

/// 聊天訊息模型
/// 對應後端 messages 表
struct ChatMessage: Codable, Identifiable, Sendable, Equatable {
    /// 訊息唯一識別碼
    let id: String
    
    /// 發送者 UID
    let senderId: String
    
    /// 訊息文字內容
    let text: String
    
    /// 發送時間
    let timestamp: Date
    
    /// 是否已讀
    var isRead: Bool
    
    /// 訊息類型（預留擴充：文字、圖片、位置分享等）
    var messageType: MessageType
    
    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case text
        case timestamp
        case createdAt = "created_at"
        case isRead = "is_read"
        case messageType = "message_type"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // id 可能是 Int 或 String
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
        
        // sender_id 可能是 Int 或 String
        if let intSender = try? container.decode(Int.self, forKey: .senderId) {
            senderId = String(intSender)
        } else {
            senderId = try container.decode(String.self, forKey: .senderId)
        }
        
        text = try container.decode(String.self, forKey: .text)
        
        // 支援 timestamp 或 created_at
        if let ts = try? container.decode(Date.self, forKey: .timestamp) {
            timestamp = ts
        } else if let ca = try? container.decode(Date.self, forKey: .createdAt) {
            timestamp = ca
        } else if let tsStr = try? container.decode(String.self, forKey: .timestamp) {
            timestamp = ISO8601DateFormatter().date(from: tsStr) ?? Date()
        } else if let caStr = try? container.decode(String.self, forKey: .createdAt) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.date(from: caStr)
                ?? ISO8601DateFormatter().date(from: caStr)
                ?? Date()
        } else {
            timestamp = Date()
        }
        
        // 後端不一定回傳這些欄位，給預設值
        isRead = (try? container.decode(Bool.self, forKey: .isRead)) ?? false
        
        if let mt = try? container.decode(MessageType.self, forKey: .messageType) {
            messageType = mt
        } else {
            messageType = .text
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(text, forKey: .text)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isRead, forKey: .isRead)
        try container.encode(messageType, forKey: .messageType)
    }
    
    // MARK: - 直接初始化
    
    init(
        id: String,
        senderId: String,
        text: String,
        timestamp: Date,
        isRead: Bool = false,
        messageType: MessageType = .text
    ) {
        self.id = id
        self.senderId = senderId
        self.text = text
        self.timestamp = timestamp
        self.isRead = isRead
        self.messageType = messageType
    }
}

// MARK: - 訊息類型

/// 訊息類型列舉
enum MessageType: String, Codable, Sendable {
    /// 純文字訊息
    case text
    /// 位置分享
    case location
    /// SOS 緊急訊息
    case sos
    /// 系統訊息（配對成功等）
    case system
}

// MARK: - 聊天歷史回應（對應後端 /api/chat/history 回傳格式）

struct ChatHistoryResponse: Codable {
    let messages: [ChatMessage]
    let hasMore: Bool
    
    enum CodingKeys: String, CodingKey {
        case messages
        case hasMore = "has_more"
    }
}

// MARK: - 便利方法

extension ChatMessage {
    /// 建立文字訊息
    static func textMessage(senderId: String, text: String) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            senderId: senderId,
            text: text,
            timestamp: Date(),
            isRead: false,
            messageType: .text
        )
    }
    
    /// 建立 SOS 緊急訊息
    static func sosMessage(senderId: String, location: Location?) -> ChatMessage {
        let locationText = if let location {
            "📍 (\(location.latitude), \(location.longitude))"
        } else {
            "（無法取得位置）"
        }
        
        return ChatMessage(
            id: UUID().uuidString,
            senderId: senderId,
            text: "🆘 緊急求助！我需要幫助！\(locationText)",
            timestamp: Date(),
            isRead: false,
            messageType: .sos
        )
    }
    
    /// 建立系統訊息
    static func systemMessage(text: String) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            senderId: "system",
            text: text,
            timestamp: Date(),
            isRead: false,
            messageType: .system
        )
    }
}
