// MainTabView.swift
// CoupleTracker
//
// 登入後的主畫面 — 底部 TabView
// 4 個 Tab：地圖、歷史、聊天、設定
// 使用 AppTheme 的粉色作為 tab bar 強調色

import SwiftUI

struct MainTabView: View {
    // MARK: - 狀態
    
    /// 目前選中的 Tab
    @State private var selectedTab: Tab = .map
    
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Tab 定義
    
    /// Tab 列舉
    enum Tab: String, CaseIterable {
        case map = "地圖"
        case history = "歷史"
        case chat = "聊天"
        case settings = "設定"
        
        /// Tab 圖示名稱
        var icon: String {
            switch self {
            case .map: return "map.fill"
            case .history: return "clock.fill"
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // 地圖頁面
            NavigationStack {
                MapView()
            }
            .tabItem {
                Label(Tab.map.rawValue, systemImage: Tab.map.icon)
            }
            .tag(Tab.map)
            
            // 歷史頁面
            NavigationStack {
                LocationHistoryView()
            }
            .tabItem {
                Label(Tab.history.rawValue, systemImage: Tab.history.icon)
            }
            .tag(Tab.history)
            
            // 聊天頁面
            NavigationStack {
                ChatView()
            }
            .tabItem {
                Label(Tab.chat.rawValue, systemImage: Tab.chat.icon)
            }
            .tag(Tab.chat)
            
            // 設定頁面
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
            }
            .tag(Tab.settings)
        }
        .tint(AppTheme.pink) // Tab bar 強調色使用主題粉色
    }
}

// MARK: - Preview

#Preview("主畫面") {
    MainTabView()
}

#Preview("深色模式") {
    MainTabView()
        .preferredColorScheme(.dark)
}
