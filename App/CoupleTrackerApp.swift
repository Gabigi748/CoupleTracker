// CoupleTrackerApp.swift
// CoupleTracker
//
// App 入口 — Firebase 初始化、全域服務注入

import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UIKit

// MARK: - App Delegate

/// App Delegate — 處理 Firebase 初始化與推播通知註冊
class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 初始化 Firebase
        FirebaseApp.configure()
        
        // 註冊遠端推播
        application.registerForRemoteNotifications()
        
        return true
    }
    
    /// 收到 APNs Token，轉交給 Firebase Messaging
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    /// 推播註冊失敗
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
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
    
    /// Firebase 服務
    @State private var firebaseService = FirebaseService()
    
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
                .environment(firebaseService)
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
        
        // 設定位置更新回調
        locationManager.onLocationUpdate = { location in
            Task {
                try? await firebaseService.updateLocation(location)
            }
        }
        
        // 同步電量
        syncBatteryLevel()
    }
    
    /// 處理圍欄事件
    private func handleGeofenceEvent(_ event: GeofenceEvent) {
        guard let zone = geofenceManager.zone(by: event.regionId),
              let partnerName = firebaseService.partner?.name ?? firebaseService.currentUser?.name else {
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
                try? await firebaseService.updateBatteryLevel(level)
            }
        }
    }
}

// MARK: - ContentView（暫時佔位）

/// 主畫面（暫時佔位，後續實作）
struct ContentView: View {
    @Environment(FirebaseService.self) private var firebaseService
    
    var body: some View {
        Group {
            if firebaseService.isAuthenticated {
                // 已登入 → 主畫面（待實作）
                Text("🗺️ CoupleTracker")
                    .font(.largeTitle)
            } else {
                // 未登入 → 登入畫面（待實作）
                Text("請登入")
                    .font(.title)
            }
        }
    }
}
