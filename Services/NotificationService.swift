// NotificationService.swift
// CoupleTracker
//
// 推播通知服務 — 本地通知、FCM 遠端推播、SOS 緊急通知

import Foundation
import Observation
import UserNotifications
import FirebaseMessaging
import FirebaseFirestore

/// 推播通知服務
/// 管理本地通知（圍欄觸發）與遠端推播（FCM）
@Observable
final class NotificationService: NSObject {
    
    // MARK: - 屬性
    
    /// 通知授權狀態
    var isAuthorized: Bool = false
    
    /// FCM Token（用於遠端推播）
    var fcmToken: String?
    
    /// 錯誤訊息
    var errorMessage: String?
    
    // MARK: - 私有屬性
    
    /// Firestore 資料庫參考
    private let db = Firestore.firestore()
    
    /// 通知中心
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // MARK: - 初始化
    
    override init() {
        super.init()
        notificationCenter.delegate = self
        Messaging.messaging().delegate = self
    }
    
    // MARK: - 權限請求
    
    /// 請求通知權限
    func requestAuthorization() async throws {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound, .criticalAlert]
        isAuthorized = try await notificationCenter.requestAuthorization(options: options)
    }
    
    /// 檢查當前通知權限狀態
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }
    
    // MARK: - 本地通知（圍欄觸發）
    
    /// 發送圍欄進入通知
    /// - Parameters:
    ///   - zoneName: 圍欄名稱
    ///   - partnerName: 對方名稱
    func sendGeofenceEntryNotification(zoneName: String, partnerName: String) {
        let content = UNMutableNotificationContent()
        content.title = "📍 到達通知"
        content.body = "\(partnerName) 已到達「\(zoneName)」"
        content.sound = .default
        content.categoryIdentifier = "GEOFENCE_EVENT"
        
        let request = UNNotificationRequest(
            identifier: "geofence_entry_\(UUID().uuidString)",
            content: content,
            trigger: nil // 立即發送
        )
        
        notificationCenter.add(request) { [weak self] error in
            if let error {
                self?.errorMessage = "通知發送失敗：\(error.localizedDescription)"
            }
        }
    }
    
    /// 發送圍欄離開通知
    /// - Parameters:
    ///   - zoneName: 圍欄名稱
    ///   - partnerName: 對方名稱
    func sendGeofenceExitNotification(zoneName: String, partnerName: String) {
        let content = UNMutableNotificationContent()
        content.title = "📍 離開通知"
        content.body = "\(partnerName) 已離開「\(zoneName)」"
        content.sound = .default
        content.categoryIdentifier = "GEOFENCE_EVENT"
        
        let request = UNNotificationRequest(
            identifier: "geofence_exit_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request)
    }
    
    // MARK: - SOS 緊急通知
    
    /// 發送 SOS 緊急本地通知
    /// - Parameters:
    ///   - senderName: 發送者名稱
    ///   - location: 發送者位置
    func sendSOSNotification(senderName: String, location: Location?) {
        let content = UNMutableNotificationContent()
        content.title = "🆘 緊急求助"
        content.body = "\(senderName) 發出了緊急求助！"
        content.sound = .defaultCritical // 使用緊急音效
        content.interruptionLevel = .critical // 突破勿擾模式
        content.categoryIdentifier = "SOS_ALERT"
        
        // 附加位置資訊
        if let location {
            content.userInfo = [
                "latitude": location.latitude,
                "longitude": location.longitude
            ]
        }
        
        let request = UNNotificationRequest(
            identifier: "sos_\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request)
    }
    
    /// 透過 FCM 發送 SOS 遠端推播給對方
    /// - Parameters:
    ///   - partnerUid: 對方 UID
    ///   - senderName: 發送者名稱
    ///   - location: 發送者位置
    func sendRemoteSOSNotification(partnerUid: String, senderName: String, location: Location?) async throws {
        // 取得對方的 FCM Token
        let document = try await db.collection("users").document(partnerUid)
            .collection("tokens")
            .document("fcm")
            .getDocument()
        
        guard let data = document.data(),
              let partnerToken = data["token"] as? String else {
            throw CoupleTrackerError.notPaired
        }
        
        // 寫入推播佇列（由 Cloud Functions 處理實際發送）
        var notificationData: [String: Any] = [
            "to_token": partnerToken,
            "title": "🆘 緊急求助",
            "body": "\(senderName) 發出了緊急求助！",
            "type": "sos",
            "created_at": Timestamp(date: Date())
        ]
        
        if let location {
            notificationData["latitude"] = location.latitude
            notificationData["longitude"] = location.longitude
        }
        
        try await db.collection("notification_queue").addDocument(data: notificationData)
    }
    
    // MARK: - FCM Token 管理
    
    /// 儲存 FCM Token 到 Firestore
    /// - Parameter uid: 用戶 UID
    func saveFCMToken(for uid: String) async throws {
        guard let token = fcmToken else { return }
        
        try await db.collection("users").document(uid)
            .collection("tokens")
            .document("fcm")
            .setData([
                "token": token,
                "updated_at": Timestamp(date: Date()),
                "platform": "ios"
            ])
    }
    
    /// 刪除 FCM Token（登出時呼叫）
    /// - Parameter uid: 用戶 UID
    func removeFCMToken(for uid: String) async throws {
        try await db.collection("users").document(uid)
            .collection("tokens")
            .document("fcm")
            .delete()
    }
    
    // MARK: - 通知分類設定
    
    /// 註冊通知動作分類
    func registerNotificationCategories() {
        // 圍欄事件分類
        let geofenceCategory = UNNotificationCategory(
            identifier: "GEOFENCE_EVENT",
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        // SOS 分類（含回應動作）
        let callAction = UNNotificationAction(
            identifier: "SOS_CALL",
            title: "📞 撥打電話",
            options: .foreground
        )
        let mapAction = UNNotificationAction(
            identifier: "SOS_MAP",
            title: "🗺️ 查看位置",
            options: .foreground
        )
        let sosCategory = UNNotificationCategory(
            identifier: "SOS_ALERT",
            actions: [callAction, mapAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        notificationCenter.setNotificationCategories([geofenceCategory, sosCategory])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    
    /// 前景收到通知時的處理
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // 前景也顯示通知（banner + 音效）
        return [.banner, .sound, .badge]
    }
    
    /// 用戶點擊通知時的處理
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionId = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        
        switch actionId {
        case "SOS_CALL":
            // 處理撥打電話動作（由 App 層處理）
            NotificationCenter.default.post(
                name: .sosCallAction,
                object: nil,
                userInfo: userInfo
            )
        case "SOS_MAP":
            // 處理查看位置動作
            NotificationCenter.default.post(
                name: .sosMapAction,
                object: nil,
                userInfo: userInfo
            )
        default:
            break
        }
    }
}

// MARK: - MessagingDelegate

extension NotificationService: MessagingDelegate {
    
    /// FCM Token 更新回調
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        self.fcmToken = fcmToken
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// SOS 撥打電話動作
    static let sosCallAction = Notification.Name("sosCallAction")
    /// SOS 查看地圖動作
    static let sosMapAction = Notification.Name("sosMapAction")
}
