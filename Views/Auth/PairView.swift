// PairView.swift
// CoupleTracker
//
// 配對頁面
// - 顯示自己的 6 位配對碼
// - 輸入對方的配對碼
// - 配對成功動畫（愛心合體）

import SwiftUI

struct PairView: View {
    // MARK: - 狀態
    @State private var myCode = ""                  // 自己的配對碼
    @State private var partnerCode = ""             // 輸入對方的配對碼
    @State private var isPairing = false            // 配對中
    @State private var isPaired = false             // 配對成功
    @State private var heartOffset: CGFloat = 100   // 愛心動畫偏移
    @State private var showConfetti = false         // 成功特效
    @State private var isGeneratingCode = false     // 正在生成配對碼
    @State private var showError = false
    @State private var errorMessage = ""
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(APIService.self) private var apiService
    
    // 配對碼每個字元拆開顯示
    private var codeCharacters: [String] {
        myCode.map { String($0) }
    }
    
    var body: some View {
        ZStack {
            // 背景
            (colorScheme == .dark
             ? AppTheme.darkBackgroundGradient
             : AppTheme.backgroundGradient)
                .ignoresSafeArea()
            
            if isPaired {
                // 配對成功畫面
                pairedSuccessView
            } else {
                // 配對輸入畫面
                pairingView
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isPaired)
        .alert("錯誤", isPresented: $showError) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .task {
            // 頁面出現時自動生成配對碼
            await generateCode()
        }
    }
    
    // MARK: - 配對輸入畫面
    private var pairingView: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer().frame(height: 20)
                
                // 標題
                VStack(spacing: 8) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(AppTheme.primaryGradient)
                    
                    Text("配對你的另一半")
                        .font(.title.bold())
                        .foregroundStyle(AppTheme.primaryGradient)
                    
                    Text("分享你的配對碼，或輸入對方的配對碼")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // 我的配對碼
                myCodeSection
                
                // 分隔線
                dividerSection
                
                // 輸入對方配對碼
                partnerCodeSection
                
                // 配對按鈕
                pairButton
                
                Spacer()
            }
            .padding(.horizontal, 32)
        }
    }
    
    // MARK: - 我的配對碼
    private var myCodeSection: some View {
        VStack(spacing: 12) {
            Text("我的配對碼")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            if isGeneratingCode {
                ProgressView()
                    .frame(height: 56)
            } else {
                // 6 位碼顯示
                HStack(spacing: 8) {
                    ForEach(Array(codeCharacters.enumerated()), id: \.offset) { _, char in
                        Text(char)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppTheme.primaryGradient)
                            .frame(width: 44, height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                                    .fill(colorScheme == .dark
                                          ? Color(.systemGray5)
                                          : .white)
                                    .shadow(color: AppTheme.pink.opacity(0.15), radius: 4, y: 2)
                            )
                    }
                }
            }
            
            // 複製按鈕
            Button {
                UIPasteboard.general.string = myCode
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                    Text("複製配對碼")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.pink)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(AppTheme.pink.opacity(0.12))
                )
            }
            .disabled(myCode.isEmpty)
        }
        .cardStyle()
    }
    
    // MARK: - 分隔線
    private var dividerSection: some View {
        HStack {
            Rectangle()
                .fill(AppTheme.softPink.opacity(0.5))
                .frame(height: 1)
            
            Text("或")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            
            Rectangle()
                .fill(AppTheme.softPurple.opacity(0.5))
                .frame(height: 1)
        }
    }
    
    // MARK: - 輸入對方配對碼
    private var partnerCodeSection: some View {
        VStack(spacing: 12) {
            Text("輸入對方的配對碼")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            TextField("例如：B2X8M4", text: $partnerCode)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                        .fill(colorScheme == .dark
                              ? Color(.systemGray5)
                              : .white)
                        .shadow(color: AppTheme.purple.opacity(0.15), radius: 4, y: 2)
                )
                .onChange(of: partnerCode) { _, newValue in
                    // 限制 6 個字元
                    if newValue.count > 6 {
                        partnerCode = String(newValue.prefix(6))
                    }
                }
        }
        .cardStyle()
    }
    
    // MARK: - 配對按鈕
    private var pairButton: some View {
        Button {
            startPairing()
        } label: {
            HStack(spacing: 8) {
                if isPairing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "heart.circle.fill")
                    Text("開始配對")
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(partnerCode.count != 6 || isPairing)
        .opacity(partnerCode.count == 6 ? 1.0 : 0.5)
    }
    
    // MARK: - 配對成功畫面
    private var pairedSuccessView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // 兩顆愛心合體動畫
            ZStack {
                // 左邊愛心（自己）
                Image(systemName: "heart.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(AppTheme.pink)
                    .offset(x: -heartOffset)
                
                // 右邊愛心（對方）
                Image(systemName: "heart.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(AppTheme.purple)
                    .offset(x: heartOffset)
                
                // 合體後的大愛心
                if showConfetti {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(AppTheme.primaryGradient)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            
            if showConfetti {
                VStack(spacing: 12) {
                    Text("配對成功！")
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.primaryGradient)
                    
                    Text("你們已經連結在一起了 💕")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            Spacer()
        }
    }
    
    // MARK: - 生成配對碼
    private func generateCode() async {
        isGeneratingCode = true
        do {
            myCode = try await apiService.generatePairCode()
        } catch {
            errorMessage = "生成配對碼失敗：\(error.localizedDescription)"
            showError = true
        }
        isGeneratingCode = false
    }
    
    // MARK: - 配對邏輯
    private func startPairing() {
        isPairing = true
        
        Task {
            do {
                try await apiService.connectWithCode(partnerCode)
                
                // 配對成功
                isPairing = false
                isPaired = true
                
                // 愛心合體動畫
                withAnimation(.easeInOut(duration: 0.8)) {
                    heartOffset = 0
                }
                
                // 顯示成功文字
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    showConfetti = true
                }
            } catch {
                isPairing = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Preview
#Preview("配對頁面") {
    PairView()
        .environment(APIService())
}

#Preview("深色模式") {
    PairView()
        .environment(APIService())
        .preferredColorScheme(.dark)
}
