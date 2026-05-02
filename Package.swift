// swift-tools-version: 6.0
// Package.swift
// CoupleTracker
//
// SPM 依賴管理 — 本專案不再需要任何外部套件
// 已移除 Firebase SDK，改用自建後端（URLSession + WebSocket）

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
        // 不再需要任何外部依賴
        // 所有網路通訊使用系統內建的 URLSession + URLSessionWebSocketTask
    ],
    targets: [
        .target(
            name: "CoupleTracker",
            dependencies: [],
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
 
 本專案已移除所有外部依賴（Firebase SDK），改用自建後端。
 
 ## 後端架構
 
 | 元件              | 技術                          |
 |------------------|-------------------------------|
 | REST API         | Express.js + MySQL            |
 | 即時通訊          | WebSocket (ws)                |
 | 推播通知          | APNs (Apple Push)             |
 | 認證              | JWT (JSON Web Token)          |
 
 ## 系統框架（無需額外安裝）
 
 | 框架               | 用途                          |
 |-------------------|-------------------------------|
 | Foundation        | URLSession、JSON 編解碼        |
 | Security          | Keychain 存取 JWT Token       |
 | CoreLocation      | GPS 定位、地理圍欄             |
 | MapKit            | 地圖顯示                      |
 | UserNotifications | 本地/遠端通知                  |
 | UIKit             | 電量監控、App 生命週期          |
 | SwiftUI           | UI 框架                       |
 | Observation       | 狀態管理（@Observable）        |
 
 ## API 端點
 
 Base URL: https://anzufish.org/couple-api
 WebSocket: wss://anzufish.org/couple-ws
 
 ============================================================
*/
