// ChatMessage.swift
// CoupleTracker
//
// 聊天訊息模型 — 情侶間的即時訊息

import Foundation

/// 聊天訊息模型
/// 對應 Firestore 中 `chats/{chatId}/messages/{id}` 文件
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
    
    /// Firestore 欄位對應
    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case text
        case timestamp
        case isRead = "is_read"
        case messageType = "message_type"
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
