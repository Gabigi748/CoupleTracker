// swift-tools-version: 6.0
// Package.swift
// CoupleTracker
//
// SPM 依賴管理 — 定義專案所需的外部套件

import PackageDescription

let package = Package(
    name: "CoupleTracker",
    platforms: [
        .iOS(.v17) // 最低支援 iOS 17
    ],
    products: [
        .library(
            name: "CoupleTracker",
            targets: ["CoupleTracker"]
        )
    ],
    dependencies: [
        // Firebase iOS SDK
        // 包含 Auth、Firestore、Messaging（FCM）
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk.git",
            from: "11.0.0"
        )
    ],
    targets: [
        .target(
            name: "CoupleTracker",
            dependencies: [
                // Firebase 認證
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                // Firestore 資料庫
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                // Firebase Cloud Messaging（推播通知）
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
            ],
            path: ".",
            exclude: ["Package.swift", "README.md"],
            sources: ["Models", "Services", "App", "Views"]
        )
    ]
)

/*
 ============================================================
 SPM 依賴說明
 ============================================================
 
 本專案使用 Swift Package Manager (SPM) 管理依賴。
 
 ## 在 Xcode 中加入依賴
 
 如果使用 Xcode 專案（而非 SPM Package）：
 
 1. File → Add Package Dependencies...
 2. 輸入 URL: https://github.com/firebase/firebase-ios-sdk.git
 3. 選擇版本規則: Up to Next Major Version → 11.0.0
 4. 選擇需要的產品：
    - FirebaseAuth（認證）
    - FirebaseFirestore（資料庫）
    - FirebaseMessaging（推播通知）
 
 ## 使用的 Firebase 模組
 
 | 模組               | 用途                          |
 |-------------------|-------------------------------|
 | FirebaseAuth      | Email 登入/註冊               |
 | FirebaseFirestore | 即時資料庫、位置同步、聊天     |
 | FirebaseMessaging | FCM 遠端推播通知              |
 
 ## 其他系統框架（無需額外安裝）
 
 | 框架            | 用途                    |
 |----------------|-------------------------|
 | CoreLocation   | GPS 定位、地理圍欄       |
 | MapKit         | 地圖顯示                |
 | UserNotifications | 本地/遠端通知         |
 | UIKit          | 電量監控、App 生命週期   |
 | SwiftUI        | UI 框架                 |
 | Observation    | 狀態管理（@Observable）  |
 
 ============================================================
*/
