// SOSView.swift
// CoupleTracker
//
// SOS 緊急求助頁面
// - 大紅色 SOS 按鈕（長按 3 秒觸發）
// - 長按時有倒數動畫（圓環進度條）
// - 觸發後顯示「已發送緊急位置給對方」
// - 可以取消（放開手指）
// - 底部顯示說明文字

import SwiftUI

struct SOSView: View {
    // MARK: - 狀態
    
    /// 長按進度（0.0 ~ 1.0）
    @State private var holdProgress: CGFloat = 0.0
    
    /// 是否正在長按
    @State private var isHolding = false
    
    /// 是否已觸發 SOS
    @State private var isTriggered = false
    
    /// 倒數計時器
    @State private var holdTimer: Timer?
    
    /// 脈動動畫
    @State private var pulseScale: CGFloat = 1.0
    
    /// 觸發後的打勾動畫
    @State private var showCheckmark = false
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    /// 長按觸發所需秒數
    private let holdDuration: TimeInterval = 3.0
    
    /// 計時器更新間隔
    private let timerInterval: TimeInterval = 0.02
    
    var body: some View {
        ZStack {
            // 背景
            backgroundLayer
            
            VStack(spacing: 32) {
                Spacer()
                
                // 標題
                headerSection
                
                Spacer()
                
                if isTriggered {
                    // 已觸發：顯示成功訊息
                    triggeredSection
                } else {
                    // 未觸發：顯示 SOS 按鈕
                    sosButtonSection
                }
                
                Spacer()
                
                // 底部說明文字
                footerSection
                
                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 32)
        }
        .navigationTitle("緊急求助")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - 背景
    private var backgroundLayer: some View {
        Group {
            if colorScheme == .dark {
                AppTheme.darkBackgroundGradient
            } else {
                AppTheme.backgroundGradient
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - 標題區域
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "sos.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.sosRed)
            
            Text("緊急求助")
                .font(.title.bold())
            
            Text("長按按鈕 3 秒發送你的位置給對方")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - SOS 按鈕區域
    private var sosButtonSection: some View {
        ZStack {
            // 外圈脈動效果（未按下時）
            if !isHolding {
                Circle()
                    .fill(AppTheme.sosRed.opacity(0.15))
                    .frame(width: 220, height: 220)
                    .scaleEffect(pulseScale)
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 1.2)
                            .repeatForever(autoreverses: true)
                        ) {
                            pulseScale = 1.1
                        }
                    }
            }
            
            // 進度圓環（長按時顯示）
            Circle()
                .trim(from: 0, to: holdProgress)
                .stroke(
                    AppTheme.sosRed,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: timerInterval), value: holdProgress)
            
            // 底圈（灰色軌道）
            Circle()
                .stroke(
                    AppTheme.sosRed.opacity(0.2),
                    lineWidth: 8
                )
                .frame(width: 200, height: 200)
            
            // SOS 按鈕本體
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppTheme.sosRed,
                            AppTheme.sosRed.opacity(0.8)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 180, height: 180)
                .shadow(
                    color: AppTheme.sosRed.opacity(isHolding ? 0.6 : 0.3),
                    radius: isHolding ? 20 : 10,
                    y: 4
                )
                .scaleEffect(isHolding ? 0.92 : 1.0)
                .overlay(
                    VStack(spacing: 8) {
                        Text("SOS")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        
                        if isHolding {
                            // 顯示倒數秒數
                            let remaining = max(0, holdDuration - (holdProgress * holdDuration))
                            Text(String(format: "%.1f 秒", remaining))
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.9))
                        } else {
                            Text("長按 3 秒")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isHolding && !isTriggered {
                                startHolding()
                            }
                        }
                        .onEnded { _ in
                            if isHolding {
                                cancelHolding()
                            }
                        }
                )
                .animation(.easeInOut(duration: 0.2), value: isHolding)
        }
    }
    
    // MARK: - 已觸發成功畫面
    private var triggeredSection: some View {
        VStack(spacing: 24) {
            // 打勾動畫
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 160, height: 160)
                
                Circle()
                    .fill(Color.green)
                    .frame(width: 120, height: 120)
                    .shadow(color: .green.opacity(0.3), radius: 12, y: 4)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(showCheckmark ? 1.0 : 0.3)
                    .opacity(showCheckmark ? 1.0 : 0.0)
            }
            
            VStack(spacing: 8) {
                Text("已發送緊急位置給對方")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
                
                Text("對方會收到你的即時位置通知")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // 返回按鈕
            Button {
                dismiss()
            } label: {
                Text("返回")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.buttonRadius)
                            .fill(AppTheme.primaryGradient)
                    )
            }
            .padding(.top, 8)
        }
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - 底部說明
    private var footerSection: some View {
        VStack(spacing: 12) {
            // 說明卡片
            VStack(alignment: .leading, spacing: 8) {
                Label("使用說明", systemImage: "info.circle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.purple)
                
                VStack(alignment: .leading, spacing: 6) {
                    instructionRow(icon: "hand.tap.fill", text: "長按紅色按鈕 3 秒觸發")
                    instructionRow(icon: "hand.raised.fill", text: "放開手指即可取消")
                    instructionRow(icon: "location.fill", text: "觸發後會發送你的即時位置")
                    instructionRow(icon: "bell.fill", text: "對方會收到緊急通知")
                }
            }
            .cardStyle()
        }
    }
    
    /// 說明列
    private func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(AppTheme.pink)
                .frame(width: 20)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - 長按邏輯
    
    /// 開始長按
    private func startHolding() {
        isHolding = true
        holdProgress = 0.0
        
        // 觸覺回饋
        let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)
        impactGenerator.impactOccurred()
        
        // 啟動計時器，逐步增加進度
        holdTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { timer in
            let increment = timerInterval / holdDuration
            holdProgress += increment
            
            if holdProgress >= 1.0 {
                // 達到 3 秒，觸發 SOS
                timer.invalidate()
                holdTimer = nil
                triggerSOS()
            }
        }
    }
    
    /// 取消長按（手指放開）
    private func cancelHolding() {
        isHolding = false
        holdTimer?.invalidate()
        holdTimer = nil
        
        // 進度歸零（帶動畫）
        withAnimation(.easeOut(duration: 0.3)) {
            holdProgress = 0.0
        }
    }
    
    /// 觸發 SOS
    private func triggerSOS() {
        isHolding = false
        
        // 成功觸覺回饋
        let notificationGenerator = UINotificationFeedbackGenerator()
        notificationGenerator.notificationOccurred(.success)
        
        // 切換到成功畫面
        withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
            isTriggered = true
        }
        
        // 打勾動畫延遲出現
        withAnimation(.spring(duration: 0.4, bounce: 0.4).delay(0.2)) {
            showCheckmark = true
        }
        
        // TODO: 呼叫 FirebaseService 發送 SOS 訊息與位置
        // TODO: 呼叫 NotificationService 發送推播給對方
    }
}

// MARK: - Preview

#Preview("SOS 頁面") {
    NavigationStack {
        SOSView()
    }
}

#Preview("深色模式") {
    NavigationStack {
        SOSView()
    }
    .preferredColorScheme(.dark)
}
