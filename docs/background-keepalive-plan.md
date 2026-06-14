# CoupleTracker iOS 後台保活改善方案

## 一、現有問題分析

### 1.1 當前後台執行策略

| 策略 | 現有實作 | 問題 |
|------|---------|------|
| Background Location Updates | ✅ `allowsBackgroundLocationUpdates = true`<br>✅ `pausesLocationUpdatesAutomatically = false`<br>✅ 背景切換至 `kCLLocationAccuracyNearestTenMeters` | 正確設定，這是最強的保活手段 |
| Significant Location Changes | ✅ 進入背景時啟動 `startMonitoringSignificantLocationChanges()` | 作為備援可以，但精度低（500m+才觸發） |
| Background Task (短時) | ⚠️ 僅用於 WebSocket 重連和位置發送（`beginBackgroundTask`） | 只有 ~30 秒執行時間，不是持久保活方案 |
| BGTaskScheduler | ❌ 完全未使用 | 缺少定期喚醒機制 |
| Silent Push (APNs) | ❌ 後端只在對方離線時發 push，且是 alert push | 沒有利用 silent push 喚醒 App |
| WebSocket 重連 | ✅ Exponential backoff，最多 50 次 | 背景下 Timer 不保證觸發 |

### 1.2 核心問題根因

1. **iOS 系統的背景政策**：即使有 `background location` 權限，iOS 仍可能在記憶體壓力大時終止 App（尤其 iPhone 記憶體 < 6GB 的舊機型）

2. **WebSocket 在背景必死**：iOS 不允許背景 App 維持長連線。進入背景約 30 秒後，所有 socket 被系統中斷。Timer 也不會觸發。

3. **單一依賴 WebSocket**：圍欄通知、聊天、螢幕狀態全靠 WebSocket 即時推送。一旦背景斷線，全部功能失效。

4. **缺少喚醒機制**：沒有 BGTaskScheduler 定期喚醒，沒有 silent push 從伺服器喚醒，App 一旦被殺就完全失聯。

5. **Live Activity 未用於 push update**：Live Activity 支援 APNs push update（`pushType: .token`），可以在不喚醒 App 的情況下更新動態島資訊。

### 1.3 Info.plist 現有設定

```xml
<key>UIBackgroundModes</key>
<array>
    <string>location</string>           <!-- ✅ 背景定位 -->
    <string>fetch</string>              <!-- ✅ Background Fetch -->
    <string>remote-notification</string> <!-- ✅ Silent Push -->
</array>
<key>NSSupportsLiveActivities</key>
<true/>
<key>NSSupportsLiveActivitiesFrequentUpdates</key>
<true/>
```

Background modes 設定正確，但 `fetch` 和 `remote-notification` 的能力沒有在代碼中充分利用。

---

## 二、推薦的多層保活策略（優先順序）

### 整體架構：「防禦深度」策略

```
┌─────────────────────────────────────────────────────┐
│  第 1 層：Background Location（最強，持續運行）         │
├─────────────────────────────────────────────────────┤
│  第 2 層：Silent Push 喚醒（伺服器定期喚醒）           │
├─────────────────────────────────────────────────────┤
│  第 3 層：BGTaskScheduler（系統排程定期喚醒）          │
├─────────────────────────────────────────────────────┤
│  第 4 層：Live Activity Push Update（不需喚醒 App）   │
├─────────────────────────────────────────────────────┤
│  第 5 層：Significant Location Change（被殺後仍能重啟）│
└─────────────────────────────────────────────────────┘
```

---

## 三、各層策略詳細方案

---

### 第 1 層：Background Location（已有，需微調）

**原理**：這是 iOS 最「尊重」的背景模式。只要 App 在持續接收位置更新，iOS 幾乎不會殺掉它。

**現有問題**：
- 背景模式下 `distanceFilter = 20`，如果使用者靜止不動，系統不會發送位置更新
- 長時間沒有位置更新 → iOS 認為 App 不需要背景時間 → 被殺

**改善方案**：

```swift
// LocationManager.swift - 背景模式改善

/// 切換到背景省電模式
/// 重點：不能讓 distanceFilter 太大，否則靜止時系統不觸發 → App 被殺
func setBackgroundAccuracy() {
    locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    // 關鍵：背景下用較小的 distanceFilter，確保即使微小移動也能觸發
    // 如果設太大（如 50m），靜止時系統認為不需要喚醒 App
    locationManager.distanceFilter = 10
    
    // 保險：如果完全靜止超過 5 分鐘，改用 kCLDistanceFilterNone
    // 讓系統以最低頻率也要回報位置（大約每分鐘一次）
    scheduleStaticFallback()
}

/// 靜止備援：長時間無位置更新時降低 filter
private var staticFallbackTimer: Timer?

private func scheduleStaticFallback() {
    staticFallbackTimer?.invalidate()
    staticFallbackTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
        Task { @MainActor in
            // 5 分鐘沒動 → 取消距離過濾，讓系統繼續回報
            self?.locationManager.distanceFilter = kCLDistanceFilterNone
            self?.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        }
    }
}
```

**額外保險** — 在 `didUpdateLocations` 中重置 timer：

```swift
// 每次收到位置更新，重置靜止 timer
staticFallbackTimer?.invalidate()
if UIApplication.shared.applicationState == .background {
    scheduleStaticFallback()
}
```

**預期效果**：App 在背景幾乎不會被 iOS 殺掉（只要有 Always Location 權限）
**限制**：需要「永遠允許」定位權限；狀態列會顯示位置指示器（已設 `showsBackgroundLocationIndicator = false`，不會顯示藍色膠囊）
**電量影響**：kCLLocationAccuracyNearestTenMeters 耗電極低

---

### 第 2 層：Silent Push Notifications（伺服器主動喚醒）

**原理**：APNs `content-available: 1` 的 silent push 可以在背景喚醒 App，給予約 30 秒的執行時間。App 可以趁機發送位置、重連 WebSocket。

**實作要點（iOS 端）**：

```swift
// AppDelegate.swift - 新增 silent push 處理

func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
) {
    // 判斷是否為 silent push（沒有 alert/badge/sound）
    let isSilent = (userInfo["aps"] as? [String: Any])?["content-available"] as? Int == 1
    
    if isSilent {
        // 被 silent push 喚醒 → 發送當前位置 + 嘗試重連 WebSocket
        handleBackgroundWakeUp(completionHandler: completionHandler)
    } else {
        completionHandler(.noData)
    }
}

private func handleBackgroundWakeUp(completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    Task {
        // 1. 請求一次位置更新
        locationManager.requestOneTimeLocation()
        
        // 2. 如果 WebSocket 斷了，嘗試重連
        if webSocketManager.connectionState != .connected,
           let token = apiService.currentToken {
            webSocketManager.connect(token: token)
        }
        
        // 3. 給系統一點時間完成
        try? await Task.sleep(for: .seconds(5))
        
        completionHandler(.newData)
    }
}
```

**實作要點（後端）**：

```javascript
// backend/services/backgroundWakeUp.js - 新增

const { sendSilentPush } = require('../utils/apns');

/**
 * 定期發送 silent push 喚醒所有在線用戶的 App
 * 間隔：每 15 分鐘（不能太頻繁，否則 iOS 會節流）
 */
function startBackgroundWakeUpService() {
  setInterval(async () => {
    try {
      // 取得所有有 device_token 且已配對的用戶
      const [users] = await db.query(
        'SELECT id, device_token FROM users WHERE device_token IS NOT NULL AND partner_id IS NOT NULL'
      );
      
      for (const user of users) {
        // 只在用戶 WebSocket 不在線時才發 silent push
        if (!isUserOnline(user.id)) {
          await sendSilentPush(user.device_token);
        }
      }
    } catch (err) {
      console.error('[WakeUp] 背景喚醒失敗:', err.message);
    }
  }, 15 * 60 * 1000); // 每 15 分鐘
}
```

```javascript
// backend/utils/apns.js - 新增 sendSilentPush

/**
 * 發送 Silent Push（背景喚醒）
 * content-available: 1，不顯示任何通知
 */
async function sendSilentPush(deviceToken) {
  if (!apnProvider || !deviceToken) return null;

  const notification = new apn.Notification();
  notification.contentAvailable = true;  // silent push 關鍵
  notification.topic = process.env.APNS_BUNDLE_ID || 'com.coupletracker.app';
  notification.priority = 5;  // silent push 必須用低優先級
  notification.pushType = 'background';  // iOS 13+ 必須指定
  notification.payload = { type: 'wake_up', timestamp: Date.now() };

  try {
    return await apnProvider.send(notification, deviceToken);
  } catch (err) {
    console.error('[APNs] Silent push 錯誤:', err.message);
    return null;
  }
}
```

**預期效果**：即使 App 被暫停（suspended），伺服器每 15 分鐘能喚醒一次
**限制**：
- iOS 會節流 silent push（每小時約 2-4 次，官方沒公開數字）
- 如果 App 被系統完全終止（terminated），silent push 仍能喚醒（重新啟動到背景）
- 但使用者強制關閉（上滑殺掉）後，silent push 不會喚醒
- `priority: 5` 不保證立即送達，可能延遲

---

### 第 3 層：BGTaskScheduler（定期排程）

**原理**：iOS 13+ 的 BGTaskScheduler 允許 App 註冊背景任務。系統會根據使用者使用習慣智慧排程執行。

**實作要點**：

```swift
// BackgroundTaskService.swift - 新增檔案

import BackgroundTasks
import CoreLocation

/// 背景任務管理器
/// 使用 BGTaskScheduler 定期喚醒 App 進行位置更新和 WebSocket 重連
final class BackgroundTaskService {
    
    /// 任務識別碼（需在 Info.plist 中註冊）
    static let refreshTaskId = "com.coupletracker.locationRefresh"
    static let processingTaskId = "com.coupletracker.locationSync"
    
    /// 註冊背景任務
    static func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: refreshTaskId,
            using: nil
        ) { task in
            handleAppRefresh(task as! BGAppRefreshTask)
        }
        
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingTaskId,
            using: nil
        ) { task in
            handleProcessingTask(task as! BGProcessingTask)
        }
    }
    
    /// 排程下一次 App Refresh（系統通常 15 分鐘~數小時後執行）
    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 最早 15 分鐘後
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BGTask] 排程 refresh 失敗: \(error)")
        }
    }
    
    /// 排程 Processing Task（用於需要更多時間的同步）
    static func scheduleProcessingTask() {
        let request = BGProcessingTaskRequest(identifier: processingTaskId)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 最早 1 小時後
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[BGTask] 排程 processing 失敗: \(error)")
        }
    }
    
    /// 處理 App Refresh Task
    private static func handleAppRefresh(_ task: BGAppRefreshTask) {
        // 排程下一次
        scheduleAppRefresh()
        
        let operationTask = Task {
            // 1. 請求一次位置
            // 2. 嘗試重連 WebSocket
            // 3. 上傳快取的離線位置
            await performBackgroundSync()
        }
        
        task.expirationHandler = {
            operationTask.cancel()
        }
        
        Task {
            await operationTask.value
            task.setTaskCompleted(success: true)
        }
    }
    
    /// 處理 Processing Task
    private static func handleProcessingTask(_ task: BGProcessingTask) {
        scheduleProcessingTask()
        
        let operationTask = Task {
            await performBackgroundSync()
            // Processing task 有更多時間（幾分鐘），可以做更多事
            await uploadCachedLocations()
        }
        
        task.expirationHandler = {
            operationTask.cancel()
        }
        
        Task {
            await operationTask.value
            task.setTaskCompleted(success: true)
        }
    }
    
    /// 背景同步核心邏輯
    @MainActor
    private static func performBackgroundSync() async {
        // 這裡需要存取全域服務（透過 shared instance 或 DI）
        // 具體實作取決於你的 DI 架構
    }
    
    /// 上傳快取的離線位置
    private static func uploadCachedLocations() async {
        // 上傳在離線期間快取的位置點
    }
}
```

**Info.plist 新增**：

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.coupletracker.locationRefresh</string>
    <string>com.coupletracker.locationSync</string>
</array>
```

**在 App 中啟動**：

```swift
// CoupleTrackerApp.swift - init() 中

init() {
    // ... 現有代碼 ...
    BackgroundTaskService.registerTasks()
}

// handleScenePhaseChange(.background) 中新增：
case .background:
    // ... 現有代碼 ...
    BackgroundTaskService.scheduleAppRefresh()
    BackgroundTaskService.scheduleProcessingTask()
```

**預期效果**：系統會智慧地在適當時機喚醒 App（通常是使用者習慣使用的時間段）
**限制**：
- 系統完全控制執行時機，無法保證精確間隔
- 在電量低、省電模式下可能不執行
- 每次執行時間有限（refresh ~30 秒，processing ~幾分鐘）

---

### 第 4 層：Live Activity Push Update（不需喚醒 App）

**原理**：Live Activity 支援透過 APNs push 直接更新內容，不需要喚醒 App。可以用來在 App 被殺的情況下仍在動態島顯示對方最新位置。

**實作要點（iOS 端）**：

```swift
// LiveActivityManager.swift - 改用 pushType: .token

private func doStartLiveActivity(myName: String, partnerName: String) {
    // ... 現有代碼 ...
    
    do {
        let activity = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: .token  // ← 關鍵改動：啟用 push update
        )
        
        // 取得 push token 並上傳到後端
        observePushToken(activity)
        
        // ... 其餘代碼 ...
    } catch { ... }
}

/// 監聽 Live Activity push token 變化
private func observePushToken(_ activity: Activity<CoupleTrackerAttributes>) {
    Task {
        for await pushToken in activity.pushTokenUpdates {
            let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()
            print("[LiveActivity] Push token: \(tokenString)")
            
            // 上傳到後端
            try? await apiService?.uploadLiveActivityToken(tokenString)
        }
    }
}
```

**後端新增 Live Activity push**：

```javascript
// backend/utils/apns.js - 新增 sendLiveActivityUpdate

/**
 * 透過 APNs 更新 Live Activity
 * 即使 App 被殺，動態島仍能顯示最新資訊
 */
async function sendLiveActivityUpdate(liveActivityToken, contentState) {
  if (!apnProvider || !liveActivityToken) return null;

  const notification = new apn.Notification();
  notification.topic = `${process.env.APNS_BUNDLE_ID}.push-type.liveactivity`;
  notification.pushType = 'liveactivity';
  notification.priority = 10;
  notification.payload = {
    "aps": {
      "timestamp": Math.floor(Date.now() / 1000),
      "event": "update",
      "content-state": contentState
    }
  };

  try {
    return await apnProvider.send(notification, liveActivityToken);
  } catch (err) {
    console.error('[APNs] Live Activity push 錯誤:', err.message);
    return null;
  }
}
```

**後端在收到位置更新時推送 Live Activity**：

```javascript
// 在 handleLocation() 中，如果對方 App 不在線：
if (!delivered && partnerLiveActivityToken) {
  await sendLiveActivityUpdate(partnerLiveActivityToken, {
    partnerName: senderName,
    partnerDistance: distance,  // 需要後端計算
    partnerBattery: battery,
    partnerActivity: "unknown",
    partnerCharging: !!charging,
    lastUpdateTime: new Date().toISOString(),
    stationarySince: null,
  });
}
```

**預期效果**：即使 App 被殺，動態島仍能顯示對方的最新位置和距離
**限制**：
- 只能更新 Live Activity UI，不能執行 App 代碼
- 需要後端計算兩人距離
- Live Activity 最多存活 12 小時（stale 後 4 小時）

---

### 第 5 層：Significant Location Change（App 被殺後重啟）

**原理**：這是唯一能在 App 被系統終止後重新啟動 App 的機制。當設備位置有顯著變化（約 500m+）時，iOS 會在背景重新啟動 App。

**現有代碼已實作**，但需要改善重啟後的行為：

```swift
// CoupleTrackerApp.swift - 改善啟動流程

private func setupServices() {
    // ... 現有代碼 ...
    
    // 檢查是否因為 significant location change 被重啟
    // 如果是背景啟動，快速建立連線
    if UIApplication.shared.applicationState == .background {
        handleBackgroundLaunch()
    }
}

private func handleBackgroundLaunch() {
    // 被 significant location change 或 silent push 喚醒
    // 快速完成核心任務：
    
    // 1. 立即開始定位（繼承背景精度）
    locationManager.startUpdatingLocation()
    locationManager.setBackgroundAccuracy()
    
    // 2. 快速建立 WebSocket（有 30 秒窗口）
    if apiService.isAuthenticated, let token = apiService.currentToken {
        webSocketManager.connect(token: token)
    }
    
    // 3. 排程 BGTask 確保後續能繼續被喚醒
    BackgroundTaskService.scheduleAppRefresh()
}
```

**預期效果**：App 被殺後，使用者移動 500m+ 就能自動重啟
**限制**：
- 需要使用者移動才能觸發（靜止時無效）
- 精度低，只有基站/Wi-Fi 定位
- 系統可能延遲數分鐘才觸發

---

## 四、WebSocket 重連策略

### 4.1 問題

現有重連使用 `Timer`，但 Timer 在背景不可靠（系統隨時可能凍結）。

### 4.2 改善方案

```swift
// WebSocketManager.swift - 改善重連機制

// MARK: - 前景重連（立即）

/// App 回到前景時立即重連
func reconnectIfNeeded() {
    guard connectionState != .connected,
          !isManualDisconnect,
          let token = self.token else { return }
    
    // 重置重連計數
    reconnectAttempts = 0
    
    // 立即重連，不等 timer
    establishConnection()
}

// MARK: - 背景重連策略

/// 排程重連（改善版：背景下不依賴 Timer）
private func scheduleReconnect() {
    guard reconnectAttempts < maxReconnectAttempts else {
        connectionState = .disconnected
        return
    }
    
    let delay = min(pow(2.0, Double(reconnectAttempts)), 60.0)
    reconnectAttempts += 1
    
    // 背景任務保護
    var bgTask: UIBackgroundTaskIdentifier = .invalid
    bgTask = UIApplication.shared.beginBackgroundTask(withName: "WSReconnect") {
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }
    
    // 使用 DispatchQueue 而非 Timer（背景更可靠）
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        Task { @MainActor in
            self?.establishConnection()
            
            // 延遲結束背景任務
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if bgTask != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTask)
                }
            }
        }
    }
}
```

### 4.3 新增：Network Path Monitor

使用 `NWPathMonitor` 偵測網路恢復，立即重連：

```swift
import Network

// 在 WebSocketManager 中新增：
private var pathMonitor: NWPathMonitor?

func startNetworkMonitoring() {
    pathMonitor = NWPathMonitor()
    pathMonitor?.pathUpdateHandler = { [weak self] path in
        Task { @MainActor in
            if path.status == .satisfied {
                // 網路恢復 → 立即嘗試重連
                self?.reconnectIfNeeded()
            }
        }
    }
    pathMonitor?.start(queue: DispatchQueue(label: "NetworkMonitor"))
}
```

---

## 五、離線位置快取

**問題**：WebSocket 斷線期間的位置資料會遺失。

**方案**：本地快取 + 重連後批次上傳

```swift
// OfflineLocationCache.swift - 新增

import Foundation
import CoreLocation

/// 離線位置快取
/// WebSocket 斷線期間快取位置，重連後批次上傳
actor OfflineLocationCache {
    
    static let shared = OfflineLocationCache()
    
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("offline_locations.json")
    }()
    
    /// 快取一筆位置
    func cache(_ location: Location) {
        var cached = loadFromDisk()
        cached.append(CachedLocation(
            latitude: location.latitude,
            longitude: location.longitude,
            accuracy: location.accuracy ?? 10,
            timestamp: location.timestamp
        ))
        
        // 最多保留 1000 筆（約 8 小時，每 30 秒一筆）
        if cached.count > 1000 {
            cached = Array(cached.suffix(1000))
        }
        
        saveToDisk(cached)
    }
    
    /// 取出所有快取並清空
    func flush() -> [CachedLocation] {
        let cached = loadFromDisk()
        saveToDisk([])
        return cached
    }
    
    private func loadFromDisk() -> [CachedLocation] {
        guard let data = try? Data(contentsOf: fileURL),
              let locations = try? JSONDecoder().decode([CachedLocation].self, from: data) else {
            return []
        }
        return locations
    }
    
    private func saveToDisk(_ locations: [CachedLocation]) {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        try? data.write(to: fileURL)
    }
}

struct CachedLocation: Codable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date
}
```

---

## 六、電量 vs 即時性平衡

### 6.1 動態精度策略（已有，需微調）

| 狀態 | 精度 | distanceFilter | 估計耗電 |
|------|------|---------------|---------|
| 靜止（背景） | hundredMeters → 3km | 50m → none | 極低 |
| 走路（背景） | nearestTenMeters | 10m | 低 |
| 開車（背景） | bestForNavigation | 20m | 中 |
| 前景 | best | 5m | 中高 |

### 6.2 新增：「省電模式」自動偵測

```swift
// 偵測系統省電模式
NotificationCenter.default.addObserver(
    forName: .NSProcessInfoPowerStateDidChange,
    object: nil,
    queue: .main
) { [weak self] _ in
    if ProcessInfo.processInfo.isLowPowerModeEnabled {
        // 省電模式：降低精度
        self?.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self?.locationManager.distanceFilter = 100
    }
}
```

### 6.3 預估電量消耗

| 策略 | 每日耗電（%） |
|------|-------------|
| Background Location (NearestTenMeters) | 2-5% |
| Significant Location Changes only | < 1% |
| Silent Push (每 15 分鐘) | < 0.5% |
| BGTaskScheduler | < 0.5% |
| 全部合計 | 3-7% |

---

## 七、後端配合改動

### 7.1 新增 API 端點

```javascript
// POST /api/live-activity-token - 上傳 Live Activity push token
router.post('/live-activity-token', auth, async (req, res) => {
  const { token } = req.body;
  await db.query(
    'UPDATE users SET live_activity_token = ? WHERE id = ?',
    [token, req.userId]
  );
  res.json({ success: true });
});

// POST /api/locations/batch - 批次上傳離線位置
router.post('/locations/batch', auth, async (req, res) => {
  const { locations } = req.body; // [{ lat, lng, accuracy, timestamp }]
  if (!locations?.length) return res.json({ success: true, count: 0 });
  
  const values = locations.map(loc => [
    req.userId, loc.lat, loc.lng, loc.accuracy, new Date(loc.timestamp)
  ]);
  
  await db.query(
    'INSERT INTO locations (user_id, lat, lng, accuracy, created_at) VALUES ?',
    [values]
  );
  
  res.json({ success: true, count: locations.length });
});
```

### 7.2 新增 DB 欄位

```sql
ALTER TABLE users ADD COLUMN live_activity_token VARCHAR(255) DEFAULT NULL;
```

### 7.3 Silent Push 服務

在後端新增 cron-style 服務，每 15 分鐘對不在線的用戶發送 silent push（見第 2 層方案）。

### 7.4 位置快取

後端在轉發位置給離線對方時，保存最新 N 筆位置。App 重連時可以一次拉取斷線期間的軌跡：

```javascript
// GET /api/partner/locations?since=<ISO timestamp>
router.get('/partner/locations', auth, async (req, res) => {
  const since = req.query.since || new Date(Date.now() - 3600000).toISOString();
  const [rows] = await db.query(
    `SELECT lat, lng, accuracy, battery, created_at as timestamp 
     FROM locations 
     WHERE user_id = (SELECT partner_id FROM users WHERE id = ?) 
       AND created_at > ?
     ORDER BY created_at ASC
     LIMIT 100`,
    [req.userId, since]
  );
  res.json({ locations: rows });
});
```

---

## 八、Apple Developer 設定需求

### 8.1 Capabilities（Xcode → Signing & Capabilities）

| Capability | 狀態 | 用途 |
|-----------|------|------|
| Background Modes → Location updates | ✅ 已有 | 背景定位 |
| Background Modes → Background fetch | ✅ 已有 | BGAppRefreshTask |
| Background Modes → Remote notifications | ✅ 已有 | Silent push |
| Background Modes → Background processing | ⚠️ 需新增 | BGProcessingTask |
| Push Notifications | ✅ 已有 | APNs |
| Live Activities | ✅ 已有 | 動態島 |

### 8.2 Info.plist 新增

```xml
<!-- 在 UIBackgroundModes 陣列新增 -->
<string>processing</string>

<!-- 新增 BGTaskScheduler 識別碼 -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.coupletracker.locationRefresh</string>
    <string>com.coupletracker.locationSync</string>
</array>
```

### 8.3 Entitlements

不需要額外的 entitlements。現有的推播和位置權限足夠。

### 8.4 App Store 審核注意

- 確保 Info.plist 中的 `NSLocationAlwaysAndWhenInUseUsageDescription` 清楚說明為什麼需要「永遠」定位
- Background Location 是 Apple 嚴格審查的項目，需要在 App Review Notes 說明這是情侶追蹤 App 的核心功能
- 不要在 App Store 描述中提到「監控」等字眼，用「分享位置」、「安全追蹤」

---

## 九、實作優先順序

| 優先級 | 策略 | 預期工時 | 效果 |
|-------|------|---------|------|
| P0 | 修復背景定位（靜止 fallback） | 2h | 解決 80% 被殺問題 |
| P1 | Silent Push 喚醒 | 4h（前端+後端） | 15 分鐘內重連 |
| P1 | WebSocket 重連 + Network Monitor | 2h | 回前景秒連 |
| P2 | BGTaskScheduler | 3h | 補充喚醒機制 |
| P2 | 離線位置快取 | 3h | 不遺失軌跡 |
| P3 | Live Activity Push Update | 6h（前端+後端） | 動態島不中斷 |

---

## 十、預期總體效果

| 場景 | 改善前 | 改善後 |
|------|--------|--------|
| 背景 10 分鐘 | 位置偶爾中斷 | 持續更新 |
| 背景 1 小時 | 高機率被殺 | 幾乎不被殺 |
| 背景 8 小時（睡覺） | 必定被殺 | 透過 silent push 定期喚醒，間歇更新 |
| App 被殺（記憶體不足） | 完全失聯 | 15 分鐘內透過 silent push 重啟 |
| App 被殺 + 使用者移動 | 完全失聯 | Significant location change 觸發重啟 |
| 使用者上滑殺掉 | 完全失聯 | Live Activity 仍可透過 push 更新 |
| WebSocket 斷線 | 等回前景才連 | 網路恢復即重連 + 喚醒時重連 |
| 圍欄通知 | 背景失效 | 背景定位持續 → 軟體圍欄持續運作 |

---

## 十一、補充：VoIP Push 評估

**結論：不建議使用**

- VoIP Push 可以 100% 喚醒 App（即使被上滑殺掉）
- 但 Apple 從 iOS 13 開始要求使用 VoIP push 的 App 必須整合 CallKit 並呈現來電畫面
- 如果用了 VoIP push 但不呈現 CallKit UI，App 會被 Apple 拒絕上架
- CoupleTracker 不是通話 App，濫用 VoIP push 會導致審核被拒甚至帳號被封

---

## 十二、補充：Live Activity 能否幫助保活？

**間接可以**：

1. Live Activity 本身不能讓 App 保持在背景運行
2. 但有 Live Activity 的 App 在系統記憶體回收時的優先級略高（Apple 未公開文件，但社群反饋如此）
3. 更重要的是：Live Activity 的 push update 機制可以在 App 被殺後仍更新 UI
4. 搭配 `pushType: .token`，後端可以繞過 App 直接更新動態島

所以 Live Activity 不是保活手段，而是**降級方案**：App 被殺了沒關係，動態島資訊仍是最新的。

---

## 總結

CoupleTracker 的後台問題核心不在於「如何讓 iOS 不殺 App」（因為系統有權隨時終止任何 App），而是建立**多層防禦機制**：

1. **盡量不被殺**：持續背景定位是最強的手段
2. **被殺後快速恢復**：Silent push + BGTask + Significant location
3. **恢復前的降級體驗**：Live Activity push update 保持動態島資訊
4. **恢復後無縫接續**：離線快取 + WebSocket 快速重連

這套方案不需要任何 private API 或違規行為，全部使用 Apple 公開的合法 API。
