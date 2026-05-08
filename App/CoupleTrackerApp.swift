// CoupleTrackerApp.swift
// CoupleTracker
//
// App 入口 — 初始化 APIService、WebSocketManager、全域服務注入
// 已移除 Firebase 依賴

import SwiftUI
import UIKit
import CoreLocation
import UserNotifications

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
    
    /// Motion & Fitness 管理器
    @State private var motionManager = MotionActivityManager()
    
    /// Live Activity 管理器
    @State private var liveActivityManager = LiveActivityManager()
    
    // MARK: - 初始化
    
    init() {
        // GeofenceManager 需要 LocationManager，所以手動初始化
        let locManager = LocationManager()
        _locationManager = State(initialValue: locManager)
        _geofenceManager = State(initialValue: GeofenceManager(locationManager: locManager))
    }
    
    // MARK: - Body
    
    /// 場景階段（前景/背景/非活躍）
    @Environment(\.scenePhase) private var scenePhase
    
    /// 追蹤 App 是否在前景（用於決定是否發本地通知）
    @State private var isInForeground: Bool = true
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationManager)
                .environment(apiService)
                .environment(webSocketManager)
                .environment(notificationService)
                .environment(geofenceManager)
                .environment(motionManager)
                .environment(liveActivityManager)
                .onAppear {
                    setupServices()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                    isInForeground = (newPhase == .active)
                }
        }
    }
    
    // MARK: - 場景階段處理
    
    /// 處理 App 前景/背景切換
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // 回到前景：恢復高精度定位 + 確保 WebSocket 連線
            locationManager.setForegroundAccuracy()
            locationManager.startUpdatingLocation()
            
            // 停止 SOS 震動通知（使用者已經看到 App 了）
            notificationService.stopSOSNotifications()
            
            // 確保 Live Activity 還活著（被系統收掉或使用者滑掉時重啟）
            if apiService.isAuthenticated {
                let myName = apiService.currentUser?.name ?? "我"
                let partnerName = apiService.partnerUser?.name ?? "對方"
                liveActivityManager.ensureLiveActivity(myName: myName, partnerName: partnerName)
            }
            
            // 恢復 motion monitoring
            if !motionManager.isMonitoring {
                motionManager.startMonitoring()
            }
            
            if apiService.isAuthenticated, let token = apiService.currentToken {
                webSocketManager.connect(token: token)
                
                // 重新載入圍欄（對方可能新增了圍欄）
                Task {
                    await geofenceManager.loadZones()
                }
                
                // 主動拉一次對方最新位置（避免 WebSocket 斷線期間沒有對方位置）
                Task {
                    if let result = try? await apiService.fetchPartnerLatestLocation() {
                        // 只在 WebSocket 還沒收到對方位置時才用 API 的資料
                        if webSocketManager.partnerLocation == nil {
                            webSocketManager.partnerLocation = result.location
                        }
                        // 電量也更新（如果 WebSocket 還沒收到）
                        if let battery = result.battery, battery >= 0, webSocketManager.partnerBattery == nil {
                            webSocketManager.partnerBattery = battery
                        }
                    }
                }
            }
            
        case .background:
            // 進入背景：降低定位精度省電，但保持更新
            locationManager.setBackgroundAccuracy()
            // 同時啟動 significant location changes 作為備援
            locationManager.startSignificantLocationMonitoring()
            // Motion monitoring 在背景保持運行（省電用，根據狀態調整 GPS）
            
        case .inactive:
            break
            
        @unknown default:
            break
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
        
        // 系統圍欄回調已停用，改用軟體圍欄（在 onLocationUpdate 裡即時檢查）
        // locationManager.onGeofenceEvent = { event in
        //     handleGeofenceEvent(event)
        // }
        
        // 設定位置更新回調 — 透過 WebSocket 發送位置 + 更新 Live Activity + 軟體圍欄檢查
        locationManager.onLocationUpdate = { location in
            Task { @MainActor in
                webSocketManager.sendLocation(location)
                
                // 軟體圍欄檢查（比 iOS 系統圍欄更即時）
                let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
                let events = geofenceManager.checkGeofences(location: clLocation)
                for event in events {
                    handleGeofenceEvent(event)
                }
                
                // 更新 Live Activity（如果有對方位置）
                if let partnerLoc = webSocketManager.partnerLocation {
                    let myLoc = CLLocation(latitude: location.latitude, longitude: location.longitude)
                    let partnerCLLoc = CLLocation(latitude: partnerLoc.latitude, longitude: partnerLoc.longitude)
                    let distance = myLoc.distance(from: partnerCLLoc)
                    let partnerName = apiService.partnerUser?.name ?? "對方"
                    
                    liveActivityManager.updateLiveActivity(
                        partnerName: partnerName,
                        distance: distance,
                        battery: webSocketManager.partnerBattery ?? -1,
                        activity: webSocketManager.partnerActivity,
                        charging: webSocketManager.partnerCharging
                    )
                }
            }
        }
        
        // 設定圍欄管理器的 API 參考
        geofenceManager.configure(with: apiService)
        
        // 如果已登入，建立 WebSocket 連線 + 載入圍欄
        if apiService.isAuthenticated, let token = apiService.currentToken {
            webSocketManager.connect(token: token)
            
            // 載入圍欄並開始監控
            Task {
                await geofenceManager.loadZones()
                
                // 初始化軟體圍欄狀態（避免首次位置更新誤觸發）
                if let currentLoc = locationManager.currentLocation {
                    let clLoc = CLLocation(latitude: currentLoc.latitude, longitude: currentLoc.longitude)
                    geofenceManager.initializeStates(currentLocation: clLoc)
                }
            }
            
            // 啟動時也拉一次對方最新位置（WebSocket 連上前就能顯示距離）
            Task {
                if let result = try? await apiService.fetchPartnerLatestLocation() {
                    if webSocketManager.partnerLocation == nil {
                        webSocketManager.partnerLocation = result.location
                    }
                    if let battery = result.battery, battery >= 0, webSocketManager.partnerBattery == nil {
                        webSocketManager.partnerBattery = battery
                    }
                }
            }
        }
        
        // 啟動 Motion & Fitness 監控
        motionManager.onActivityChanged = { activity in
            Task { @MainActor in
                // 智慧調整定位精度
                locationManager.adjustAccuracyForActivity(activity)
                // 發送移動狀態給對方
                webSocketManager.sendMotionActivity(activity.rawValue)
            }
        }
        motionManager.startMonitoring()
        
        // 啟動 Live Activity
        if apiService.isAuthenticated {
            let myName = apiService.currentUser?.name ?? "我"
            let partnerName = apiService.partnerUser?.name ?? "對方"
            liveActivityManager.startLiveActivity(myName: myName, partnerName: partnerName)
        }
        
        // 同步電量
        syncBatteryLevel()
        
        // 啟動定位更新
        locationManager.startUpdatingLocation()
    }
    
    /// 處理圍欄事件
    private func handleGeofenceEvent(_ event: GeofenceEvent) {
        guard let zone = geofenceManager.zone(by: event.regionId) else {
            print("[Geofence] 找不到圍欄 ID: \(event.regionId)，已載入 \(geofenceManager.zones.count) 個圍欄: \(geofenceManager.zones.map { $0.id })")
            return
        }
        
        print("[Geofence] 觸發圍欄事件: \(zone.name) - \(event.type)")
        
        // 透過 WebSocket 發送圍欄事件給後端（後端會轉發給配對對象）
        let eventType = event.type == .entry ? "entry" : "exit"
        webSocketManager.sendGeofenceEvent(zoneName: zone.name, event: eventType)
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
    @Environment(WebSocketManager.self) private var webSocketManager
    @Environment(NotificationService.self) private var notificationService
    @Environment(LocationManager.self) private var locationManager
    @Environment(LiveActivityManager.self) private var liveActivityManager
    @Environment(\.scenePhase) private var scenePhase
    
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
        .onChange(of: webSocketManager.partnerScreenEvent) { _, event in
            guard let event else { return }
            // 只在 App 不在前景時發本地通知
            // 前景時聊天框已經顯示系統訊息，不需要額外通知
            // 背景時如果 WebSocket 還連著會走這裡，如果斷了後端會發 APNs 推播
            if scenePhase != .active {
                let partnerName = apiService.partnerUser?.name ?? "對方"
                notificationService.sendScreenStatusNotification(
                    partnerName: partnerName,
                    screenOn: event.screenOn
                )
            }
        }
        .onChange(of: webSocketManager.partnerGeofenceEvent) { _, event in
            guard let event else { return }
            // 同理，只在非前景時發本地通知
            if scenePhase != .active {
                if event.event == "entry" {
                    notificationService.sendGeofenceEntryNotification(
                        zoneName: event.zoneName,
                        partnerName: event.senderName
                    )
                } else {
                    notificationService.sendGeofenceExitNotification(
                        zoneName: event.zoneName,
                        partnerName: event.senderName
                    )
                }
            }
        }
        .onChange(of: webSocketManager.partnerLocation?.timestamp) { _, _ in
            // 收到對方位置更新時，更新 Live Activity
            guard let partnerLoc = webSocketManager.partnerLocation,
                  let myLoc = locationManager.currentLocation else { return }
            let myCLLoc = CLLocation(latitude: myLoc.latitude, longitude: myLoc.longitude)
            let partnerCLLoc = CLLocation(latitude: partnerLoc.latitude, longitude: partnerLoc.longitude)
            let distance = myCLLoc.distance(from: partnerCLLoc)
            let partnerName = apiService.partnerUser?.name ?? "對方"
            
            liveActivityManager.updateLiveActivity(
                partnerName: partnerName,
                distance: distance,
                battery: webSocketManager.partnerBattery ?? -1,
                activity: webSocketManager.partnerActivity,
                charging: webSocketManager.partnerCharging
            )
        }
    }
}
