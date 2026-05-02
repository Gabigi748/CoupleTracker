// Info.plist 權限說明
// CoupleTracker
//
// 以下為 Info.plist 中需要設定的權限描述字串
// 在 Xcode 中的 Info.plist 或 Target → Info → Custom iOS Target Properties 中設定

/*
 ============================================================
 必要的 Info.plist 權限設定
 ============================================================
 
 1. 定位權限（Core Location）
 ─────────────────────────────
 
 Key: NSLocationAlwaysAndWhenInUseUsageDescription
 Value: CoupleTracker 需要持續取得您的位置，以便與伴侶即時共享位置資訊，並在您進出設定的區域時發送通知。
 
 Key: NSLocationWhenInUseUsageDescription
 Value: CoupleTracker 需要取得您的位置，以便在地圖上顯示您的位置並與伴侶共享。
 
 Key: NSLocationAlwaysUsageDescription
 Value: CoupleTracker 需要在背景持續取得您的位置，以便伴侶隨時知道您的位置，並啟用地理圍欄通知功能。
 
 2. 背景模式（Background Modes）
 ─────────────────────────────
 
 Key: UIBackgroundModes
 Value: (Array)
   - location          → 背景定位更新
   - fetch             → 背景資料擷取
   - remote-notification → 遠端推播通知
 
 3. 推播通知
 ─────────────────────────────
 
 需要在 Apple Developer Portal 中啟用 Push Notifications capability
 並在 Xcode 的 Signing & Capabilities 中加入：
   - Push Notifications
   - Background Modes (Remote notifications)
 
 4. 其他建議設定
 ─────────────────────────────
 
 Key: UIRequiresFullScreen
 Value: YES（建議全螢幕以確保定位精確度）
 
 Key: NSUserTrackingUsageDescription
 Value: （如果未來加入廣告才需要）
 
 ============================================================
 後端設定
 ============================================================
 
 本專案使用自建後端（Express + MySQL + WebSocket）
 API Base URL: https://anzufish.org/couple-api
 WebSocket URL: wss://anzufish.org/couple-ws
 不需要 GoogleService-Info.plist
 
 ============================================================
 Xcode Project 設定
 ============================================================
 
 Target → Signing & Capabilities:
 1. + Push Notifications
 2. + Background Modes
    ✓ Location updates
    ✓ Background fetch
    ✓ Remote notifications
 3. + Maps（如果使用 MapKit）
 
 ============================================================
*/
