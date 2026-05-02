// AppTheme.swift
// CoupleTracker
//
// 全域主題色彩與樣式定義
// 暖色調（粉色 + 紫色漸層）、圓角卡片風格

import SwiftUI

// MARK: - 主題色彩
enum AppTheme {
    // 主色調
    static let pink = Color(red: 1.0, green: 0.4, blue: 0.6)
    static let purple = Color(red: 0.6, green: 0.4, blue: 0.9)
    static let softPink = Color(red: 1.0, green: 0.7, blue: 0.8)
    static let softPurple = Color(red: 0.8, green: 0.7, blue: 1.0)
    
    // 漸層
    static let primaryGradient = LinearGradient(
        colors: [pink, purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let softGradient = LinearGradient(
        colors: [softPink, softPurple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.95, blue: 0.97),
            Color(red: 0.95, green: 0.93, blue: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // 深色模式背景漸層
    static let darkBackgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.12, green: 0.1, blue: 0.15),
            Color(red: 0.08, green: 0.06, blue: 0.12)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // SOS 紅色
    static let sosRed = Color(red: 1.0, green: 0.2, blue: 0.2)
    
    // 卡片圓角半徑
    static let cardRadius: CGFloat = 20
    static let buttonRadius: CGFloat = 16
    static let smallRadius: CGFloat = 12
}

// MARK: - 卡片樣式 Modifier
struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                    .fill(colorScheme == .dark
                          ? Color(.systemGray6)
                          : .white)
                    .shadow(
                        color: AppTheme.pink.opacity(colorScheme == .dark ? 0.1 : 0.15),
                        radius: 10,
                        y: 4
                    )
            )
    }
}

// MARK: - 主要按鈕樣式
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.buttonRadius)
                    .fill(AppTheme.primaryGradient)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - View Extension
extension View {
    /// 套用卡片樣式（圓角 + 陰影）
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
    
    /// 適應深色/淺色模式的背景漸層
    func appBackground() -> some View {
        self.background(
            Group {
                AppTheme.backgroundGradient
            }
            .ignoresSafeArea()
        )
    }
}
