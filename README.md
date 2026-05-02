# CoupleTracker

情侶位置共享 iOS App — 隨時知道對方在哪裡。

## 功能

- 即時位置共享（地圖上顯示雙方位置）
- 距離顯示（你們相隔多遠）
- 背景定位更新（省電模式）
- 地理圍欄通知（到達/離開指定地點自動通知）
- 位置歷史紀錄（時間軸 + 地圖軌跡）
- SOS 緊急按鈕（長按 3 秒發送位置給對方）
- 電量同步顯示
- 簡易聊天
- 6 位配對碼綁定情侶

## 技術棧

- **UI:** Swift 6 + SwiftUI + MapKit (iOS 17+)
- **後端:** Firebase (Auth + Firestore + Cloud Messaging)
- **定位:** Core Location (背景定位 + 地理圍欄)
- **推播:** APNs + Firebase Cloud Messaging

## 專案結構

```
CoupleTracker/
├── App/                    # App 入口
│   ├── CoupleTrackerApp.swift
│   └── InfoPlist-Permissions.swift
├── Models/                 # 資料模型
│   ├── User.swift
│   ├── Location.swift
│   ├── GeofenceZone.swift
│   └── ChatMessage.swift
├── Services/               # 業務邏輯
│   ├── LocationManager.swift
│   ├── FirebaseService.swift
│   ├── GeofenceManager.swift
│   └── NotificationService.swift
├── Views/                  # UI 頁面
│   ├── Auth/               # 登入 + 配對
│   ├── Map/                # 主地圖
│   ├── History/            # 位置歷史
│   ├── Chat/               # 聊天
│   ├── SOS/                # 緊急按鈕
│   ├── Settings/           # 設定 + 圍欄管理
│   ├── Main/               # TabView + 啟動畫面
│   └── Components/         # 共用元件
├── Package.swift           # SPM 依賴
└── .github/workflows/      # CI 自動編譯
```

## 設定步驟

### 1. Firebase 設定
1. 到 [Firebase Console](https://console.firebase.google.com/) 建立專案
2. 新增 iOS App，Bundle ID 填 `com.fish.coupletracker`
3. 下載 `GoogleService-Info.plist` 放到專案根目錄
4. 啟用 Authentication (Email/Password)
5. 建立 Firestore Database
6. 設定 Cloud Messaging

### 2. Xcode 開啟
```bash
# clone 專案
git clone https://github.com/Gabigi748/CoupleTracker.git
cd CoupleTracker

# 用 Xcode 開啟
open Package.swift
```

### 3. Info.plist 權限
在 Xcode 的 Info.plist 加入以下 key：
- `NSLocationWhenInUseUsageDescription` — 需要您的位置來顯示在地圖上
- `NSLocationAlwaysAndWhenInUseUsageDescription` — 需要背景定位來即時更新位置給對方
- `UIBackgroundModes` — `location`, `remote-notification`

### 4. Build & Run
- 選擇你的 iPhone 或模擬器
- Cmd + R 執行

## CI/CD

專案包含 GitHub Actions workflow，push 到 main 會自動：
1. 在 macOS runner 上編譯
2. 產出未簽名的 .ipa
3. 上傳為 artifact 供下載

下載 .ipa 後可用第三方簽名服務簽名安裝。

## 授權

Private — 僅供個人使用
