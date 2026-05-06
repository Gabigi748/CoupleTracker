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
        content.title = "到達通知"
        content.body = "\(partnerName) 已到達「\(zoneName)」"
        content.sound = .default
        content.categoryIdentifier = "GEOFENCE_EVENT"
        
        let request = UNNotificationRequest(
            identifier: "geofence_entry_\(zoneName)",
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
        content.title = "離開通知"
        content.body = "\(partnerName) 已離開「\(zoneName)」"
        content.sound = .default
        content.categoryIdentifier = "GEOFENCE_EVENT"
        
        let request = UNNotificationRequest(
            identifier: "geofence_exit_\(zoneName)",
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request)
    }
    
    // MARK: - SOS 緊急通知
    
    /// SOS 震動通知的固定識別碼（用於停止）
    private let sosNotificationPrefix = "sos_alert_"
    
    /// 發送 SOS 緊急本地通知
    /// 會排程 30 次連續通知，每 3 秒一次，總共震動約 90 秒
    /// 使用者點開 App 或手動停止才會中斷
    /// - Parameters:
    ///   - senderName: 發送者名稱
    ///   - location: 發送者位置
    func sendSOSNotification(senderName: String, location: Location?) {
        // 先清掉舊的 SOS 通知
        stopSOSNotifications()
        
        // 排程 30 次通知，每 3 秒一次
        let totalCount = 30
        let intervalSeconds: TimeInterval = 3
        
        for i in 0..<totalCount {
            let content = UNMutableNotificationContent()
            content.title = "緊急求助"
            content.body = "\(senderName) 發出了緊急求助！請盡快回應"
            content.sound = .defaultCritical
            content.interruptionLevel = .critical
            content.categoryIdentifier = "SOS_ALERT"
            
            if let location {
                content.userInfo = [
                    "latitude": location.latitude,
                    "longitude": location.longitude,
                    "sos_index": i
                ]
            }
            
            // 第一個立即發，後面的用 trigger 排程
            let trigger: UNNotificationTrigger?
            if i == 0 {
                trigger = nil
            } else {
                trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: Double(i) * intervalSeconds,
                    repeats: false
                )
            }
            
            let request = UNNotificationRequest(
                identifier: "\(sosNotificationPrefix)\(i)",
                content: content,
                trigger: trigger
            )
            
            notificationCenter.add(request)
        }
    }
    
    /// 停止所有 SOS 通知（點開 App 時呼叫）
    func stopSOSNotifications() {
        // 找出所有待發的 SOS 通知
        notificationCenter.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let sosIds = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(self.sosNotificationPrefix) }
            if !sosIds.isEmpty {
                self.notificationCenter.removePendingNotificationRequests(withIdentifiers: sosIds)
            }
        }
        
        // 也清掉已送達但還留在通知中心的
        notificationCenter.getDeliveredNotifications { [weak self] notifications in
            guard let self else { return }
            let sosIds = notifications
                .map(\.request.identifier)
                .filter { $0.hasPrefix(self.sosNotificationPrefix) }
            if !sosIds.isEmpty {
                self.notificationCenter.removeDeliveredNotifications(withIdentifiers: sosIds)
            }
        }
    }
    
    // MARK: - 螢幕狀態通知
    
    /// 發送對方螢幕開關通知
    /// - Parameters:
    ///   - partnerName: 對方名稱
    ///   - screenOn: 螢幕是否開啟
    func sendScreenStatusNotification(partnerName: String, screenOn: Bool) {
        let content = UNMutableNotificationContent()
        
        if screenOn {
            content.title = "螢幕開啟"
            content.body = "\(partnerName) 開啟了螢幕"
        } else {
            content.title = "螢幕關閉"
            content.body = "\(partnerName) 關閉了螢幕"
        }
        
        content.sound = .default
        content.categoryIdentifier = "SCREEN_STATUS"
        
        // 用固定 ID，新通知會取代舊的，避免重複
        let request = UNNotificationRequest(
            identifier: "screen_\(screenOn ? "on" : "off")",
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
        
        // 螢幕狀態分類
        let screenCategory = UNNotificationCategory(
            identifier: "SCREEN_STATUS",
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        notificationCenter.setNotificationCategories([geofenceCategory, sosCategory, screenCategory])
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
        let notifId = response.notification.request.identifier
        
        // 如果點到的是 SOS 通知（任何 action 包括預設點擊），停止所有 SOS 震動
        if notifId.hasPrefix("sos_alert_") || actionId == "SOS_CALL" || actionId == "SOS_MAP" {
            await MainActor.run {
                self.stopSOSNotifications()
            }
        }
        
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
