// CoupleTrackerApp.swift
// CoupleTracker
//
// App 入口 — 初始化 APIService、WebSocketManager、全域服務注入
// 已移除 Firebase 依賴

import SwiftUI
import UIKit

// MARK: - App Delegate

/// App Delegate — 處理推播通知註冊與 APNs Token
class AppDelegate: NSObject, UIApplicationDelegate {
    
    /// 通知服務參考（由 App 注入）
    var notificationService: NotificationService?
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 註冊遠端推播（APNs）
        application.registerForRemoteNotifications()
        return true
    }
    
    /// 收到 APNs Device Token
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        notificationService?.handleDeviceToken(deviceToken)
    }
    
    /// 推播註冊失敗
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        notificationService?.handleRegistrationError(error)
        print("❌ 推播註冊失敗：\(error.localizedDescription)")
    }
}

// MARK: - App 入口

/// CoupleTracker App 主入口
@main
struct CoupleTrackerApp: App {
    
    // 連接 App Delegate
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    // MARK: - 全域服務（使用 @State 確保生命週期）
    
    /// 位置管理器
    @State private var locationManager: LocationManager
    
    /// API 服務（取代原本的 FirebaseService）
    @State private var apiService = APIService()
    
    /// WebSocket 管理器（即時通訊）
    @State private var webSocketManager = WebSocketManager()
    
    /// 通知服務
    @State private var notificationService = NotificationService()
    
    /// 圍欄管理器
    @State private var geofenceManager: GeofenceManager
    
    // MARK: - 初始化
    
    init() {
        // GeofenceManager 需要 LocationManager，所以手動初始化
        let locManager = LocationManager()
        _locationManager = State(initialValue: locManager)
        _geofenceManager = State(initialValue: GeofenceManager(locationManager: locManager))
    }
    
    // MARK: - Body
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationManager)
                .environment(apiService)
                .environment(webSocketManager)
                .environment(notificationService)
                .environment(geofenceManager)
                .onAppear {
                    setupServices()
                }
        }
    }
    
    // MARK: - 服務設定
    
    /// 初始化各項服務
    private func setupServices() {
        // 設定 App Delegate 的通知服務參考
        delegate.notificationService = notificationService
        
        // 設定通知服務的 API 參考
        notificationService.configure(with: apiService)
        
        // 請求通知權限
        Task {
            try? await notificationService.requestAuthorization()
            notificationService.registerNotificationCategories()
        }
        
        // 請求定位權限
        locationManager.requestAlwaysAuthorization()
        
        // 設定圍欄事件回調
        locationManager.onGeofenceEvent = { event in
            handleGeofenceEvent(event)
        }
        
        // 設定位置更新回調 — 透過 WebSocket 發送位置
        locationManager.onLocationUpdate = { location in
            Task { @MainActor in
                webSocketManager.sendLocation(location)
            }
        }
        
        // 如果已登入，建立 WebSocket 連線
        if apiService.isAuthenticated, let token = apiService.currentToken {
            webSocketManager.connect(token: token)
        }
        
        // 同步電量
        syncBatteryLevel()
        
        // 啟動定位更新
        locationManager.startUpdatingLocation()
    }
    
    /// 處理圍欄事件
    private func handleGeofenceEvent(_ event: GeofenceEvent) {
        guard let zone = geofenceManager.zone(by: event.regionId),
              let partnerName = apiService.partnerUser?.name ?? apiService.currentUser?.name else {
            return
        }
        
        switch event.type {
        case .entry:
            notificationService.sendGeofenceEntryNotification(
                zoneName: zone.name,
                partnerName: partnerName
            )
        case .exit:
            notificationService.sendGeofenceExitNotification(
                zoneName: zone.name,
                partnerName: partnerName
            )
        }
    }
    
    /// 同步裝置電量
    private func syncBatteryLevel() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = Int(UIDevice.current.batteryLevel * 100)
        if level >= 0 {
            Task {
                try? await apiService.updateBatteryLevel(level)
            }
        }
    }
}

// MARK: - ContentView

/// 主畫面 — 根據登入狀態切換
struct ContentView: View {
    @Environment(APIService.self) private var apiService
    
    var body: some View {
        Group {
            if apiService.isAuthenticated {
                if apiService.isRestoringSession {
                    // 正在恢復 session，顯示 loading
                    ZStack {
                        Color(.systemBackground).ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("載入中...")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if apiService.currentUser?.isPaired == true {
                    // 已登入且已配對 → 主畫面
                    MainTabView()
                } else {
                    // 已登入但未配對 → 配對頁面
                    NavigationStack {
                        PairView()
                    }
                }
            } else {
                // 未登入 → 登入畫面
                LoginView()
            }
        }
    }
}
