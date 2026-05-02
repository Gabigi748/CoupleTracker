// NotificationService.swift
// CoupleTracker
//
// 推播通知服務 — 本地通知 + APNs Token 上傳到自建後端
// 已移除 FCM 依賴，改用 APNs 直接推播

import Foundation
import Observation
import UserNotifications
import UIKit

/// 推播通知服務
/// 管理本地通知（圍欄觸發、SOS）與 APNs Token 上傳
@MainActor
@Observable
final class NotificationService: NSObject {
    
    // MARK: - 屬性
    
    /// 通知授權狀態
    var isAuthorized: Bool = false
    
    /// APNs Device Token（十六進位字串）
    var deviceToken: String?
    
    /// 錯誤訊息
    var errorMessage: String?
    
    // MARK: - 私有屬性
    
    /// 通知中心
    private nonisolated(unsafe) let notificationCenter = UNUserNotificationCenter.current()
    
    /// API 服務參考（用於上傳 Token）
    private weak var apiService: APIService?
    
    // MARK: - 初始化
    
    override init() {
        super.init()
        notificationCenter.delegate = self
    }
    
    /// 設定 API 服務參考
    /// - Parameter apiService: APIService 實例
    func configure(with apiService: APIService) {
        self.apiService = apiService
    }
    
    // MARK: - 權限請求
    
    /// 請求通知權限
    func requestAuthorization() async throws {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound, .criticalAlert]
        isAuthorized = try await notificationCenter.requestAuthorization(options: options)
    }
    
    /// 檢查當前通知權限狀態
    func checkAuthorizationStatus() async {
        let center = notificationCenter
        let authorized = await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus == .authorized)
            }
        }
        isAuthorized = authorized
    }
    
    // MARK: - APNs Token 處理
    
    /// 處理收到的 APNs Device Token
    /// - Parameter tokenData: 原始 token 資料
    func handleDeviceToken(_ tokenData: Data) {
        // 轉換為十六進位字串
        let tokenString = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = tokenString
        
        // 上傳到自建後端
        Task {
            do {
                try await apiService?.uploadAPNsToken(tokenString)
            } catch {
                errorMessage = "APNs Token 上傳失敗：\(error.localizedDescription)"
            }
        }
    }
    
    /// 推播註冊失敗處理
    /// - Parameter error: 錯誤
    func handleRegistrationError(_ error: Error) {
        errorMessage = "推播註冊失敗：\(error.localizedDescription)"
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
                Task { @MainActor [weak self] in
                    self?.errorMessage = "通知發送失敗：\(error.localizedDescription)"
                }
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

extension NotificationService: @preconcurrency UNUserNotificationCenterDelegate {
    
    /// 前景收到通知時的處理
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // 前景也顯示通知（banner + 音效）
        return [.banner, .sound, .badge]
    }
    
    /// 用戶點擊通知時的處理
    nonisolated func userNotificationCenter(
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

// MARK: - Notification Names

extension Notification.Name {
    /// SOS 撥打電話動作
    static let sosCallAction = Notification.Name("sosCallAction")
    /// SOS 查看地圖動作
    static let sosMapAction = Notification.Name("sosMapAction")
}
