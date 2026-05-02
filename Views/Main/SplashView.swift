// SplashView.swift
// CoupleTracker
//
// 啟動畫面
// - 中間大愛心動畫（縮放 + 脈動效果）
// - App 名稱「CoupleTracker」
// - 副標題「Always Together」
// - 2 秒後自動跳轉
// - 背景使用 AppTheme 漸層色

import SwiftUI

struct SplashView: View {
    // MARK: - 動畫狀態
    
    /// 愛心縮放
    @State private var heartScale: CGFloat = 0.3
    
    /// 愛心透明度
    @State private var heartOpacity: CGFloat = 0.0
    
    /// 脈動效果
    @State private var isPulsing = false
    
    /// 文字出現
    @State private var showText = false
    
    /// 副標題出現
    @State private var showSubtitle = false
    
    /// 是否完成（準備跳轉）
    @State private var isFinished = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // 背景漸層
            backgroundLayer
            
            // 裝飾粒子（小愛心散落）
            decorativeHearts
            
            // 主要內容
            VStack(spacing: 24) {
                Spacer()
                
                // 愛心動畫
                heartAnimation
                
                // App 名稱
                if showText {
                    Text("小寧和魚魚")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
                // 副標題
                if showSubtitle {
                    Text("Always Together")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .tracking(4)
                        .transition(.opacity)
                }
                
                Spacer()
                Spacer()
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    // MARK: - 背景
    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                AppTheme.pink,
                AppTheme.purple,
                AppTheme.purple.opacity(0.8)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    // MARK: - 裝飾小愛心
    private var decorativeHearts: some View {
        ZStack {
            // 散落的小愛心裝飾
            ForEach(0..<6, id: \.self) { index in
                Image(systemName: "heart.fill")
                    .font(.system(size: CGFloat.random(in: 10...20)))
                    .foregroundStyle(.white.opacity(0.15))
                    .offset(
                        x: CGFloat([-120, 100, -80, 130, -60, 90][index]),
                        y: CGFloat([-200, -150, 100, 180, -50, 250][index])
                    )
                    .scaleEffect(isPulsing ? 1.2 : 0.8)
                    .animation(
                        .easeInOut(duration: Double.random(in: 1.5...2.5))
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: isPulsing
                    )
            }
        }
    }
    
    // MARK: - 愛心動畫
    private var heartAnimation: some View {
        ZStack {
            // 外圈光暈（脈動）
            Circle()
                .fill(.white.opacity(0.1))
                .frame(width: 160, height: 160)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .animation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true),
                    value: isPulsing
                )
            
            // 中圈光暈
            Circle()
                .fill(.white.opacity(0.15))
                .frame(width: 120, height: 120)
                .scaleEffect(isPulsing ? 1.15 : 0.95)
                .animation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                    .delay(0.1),
                    value: isPulsing
                )
            
            // 愛心本體
            Image(systemName: "heart.fill")
                .font(.system(size: 80))
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(0.5), radius: 20)
                .scaleEffect(heartScale)
                .opacity(heartOpacity)
                // 脈動效果
                .scaleEffect(isPulsing ? 1.05 : 0.95)
                .animation(
                    .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true),
                    value: isPulsing
                )
        }
    }
    
    // MARK: - 動畫序列
    private func startAnimations() {
        // 第一階段：愛心彈入（0 ~ 0.6 秒）
        withAnimation(.spring(duration: 0.6, bounce: 0.4)) {
            heartScale = 1.0
            heartOpacity = 1.0
        }
        
        // 第二階段：開始脈動（0.5 秒後）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isPulsing = true
        }
        
        // 第三階段：顯示 App 名稱（0.8 秒後）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                showText = true
            }
        }
        
        // 第四階段：顯示副標題（1.2 秒後）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeIn(duration: 0.4)) {
                showSubtitle = true
            }
        }
        
        // 第五階段：完成，準備跳轉（2 秒後）
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeOut(duration: 0.3)) {
                isFinished = true
            }
            // TODO: 通知外層切換到登入/主畫面
            // 可透過 Binding<Bool> 或 Notification 通知 App 層
        }
    }
}

// MARK: - Preview

#Preview("啟動畫面") {
    SplashView()
}

#Preview("深色模式") {
    SplashView()
        .preferredColorScheme(.dark)
}
