// LoginView.swift
// CoupleTracker
//
// 登入 / 註冊頁面
// - Email + 密碼輸入
// - 登入 / 註冊模式切換
// - 暖色調漸層背景 + 愛心裝飾

import SwiftUI

struct LoginView: View {
    // MARK: - 狀態
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var name = ""                  // 註冊時的顯示名稱
    @State private var isRegistering = false      // 切換登入/註冊
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var heartScale: CGFloat = 1.0  // 愛心動畫
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(APIService.self) private var apiService
    
    var body: some View {
        ZStack {
            // 背景漸層
            backgroundLayer
            
            ScrollView {
                VStack(spacing: 28) {
                    Spacer().frame(height: 40)
                    
                    // Logo 區域
                    logoSection
                    
                    // 輸入表單
                    formSection
                    
                    // 登入/註冊按鈕
                    actionButton
                    
                    // 切換模式
                    toggleModeButton
                    
                    Spacer()
                }
                .padding(.horizontal, 32)
            }
        }
        .alert("錯誤", isPresented: $showError) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // 愛心跳動動畫
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                heartScale = 1.15
            }
        }
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
    
    // MARK: - Logo 區域
    private var logoSection: some View {
        VStack(spacing: 12) {
            // 愛心圖示
            Image(systemName: "heart.fill")
                .font(.system(size: 64))
                .foregroundStyle(AppTheme.primaryGradient)
                .scaleEffect(heartScale)
            
            Text("小寧和魚魚")
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.primaryGradient)
            
            Text("與你的另一半，時刻相連 💕")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - 輸入表單
    private var formSection: some View {
        VStack(spacing: 16) {
            // 名稱輸入框（僅註冊模式）
            if isRegistering {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundStyle(AppTheme.purple)
                        .frame(width: 24)
                    TextField("顯示名稱", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                        .fill(colorScheme == .dark
                              ? Color(.systemGray5)
                              : .white)
                        .shadow(color: AppTheme.purple.opacity(0.1), radius: 5, y: 2)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Email 輸入框
            HStack {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(AppTheme.pink)
                    .frame(width: 24)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                    .fill(colorScheme == .dark
                          ? Color(.systemGray5)
                          : .white)
                    .shadow(color: AppTheme.pink.opacity(0.1), radius: 5, y: 2)
            )
            
            // 密碼輸入框
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(AppTheme.purple)
                    .frame(width: 24)
                SecureField("密碼", text: $password)
                    .textContentType(isRegistering ? .newPassword : .password)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                    .fill(colorScheme == .dark
                          ? Color(.systemGray5)
                          : .white)
                    .shadow(color: AppTheme.purple.opacity(0.1), radius: 5, y: 2)
            )
            
            // 確認密碼（僅註冊模式）
            if isRegistering {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(AppTheme.purple)
                        .frame(width: 24)
                    SecureField("確認密碼", text: $confirmPassword)
                        .textContentType(.newPassword)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                        .fill(colorScheme == .dark
                              ? Color(.systemGray5)
                              : .white)
                        .shadow(color: AppTheme.purple.opacity(0.1), radius: 5, y: 2)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isRegistering)
    }
    
    // MARK: - 登入/註冊按鈕
    private var actionButton: some View {
        Button {
            performAction()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: isRegistering ? "person.badge.plus" : "arrow.right.circle.fill")
                    Text(isRegistering ? "註冊" : "登入")
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading)
    }
    
    // MARK: - 切換登入/註冊
    private var toggleModeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                isRegistering.toggle()
                confirmPassword = ""
                name = ""
            }
        } label: {
            HStack(spacing: 4) {
                Text(isRegistering ? "已有帳號？" : "還沒有帳號？")
                    .foregroundStyle(.secondary)
                Text(isRegistering ? "登入" : "註冊")
                    .foregroundStyle(AppTheme.pink)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
    }
    
    // MARK: - 動作處理
    private func performAction() {
        // 基本驗證
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "請填寫所有欄位"
            showError = true
            return
        }
        
        if isRegistering {
            guard !name.isEmpty else {
                errorMessage = "請填寫顯示名稱"
                showError = true
                return
            }
            guard password == confirmPassword else {
                errorMessage = "兩次密碼不一致"
                showError = true
                return
            }
        }
        
        isLoading = true
        
        Task {
            do {
                if isRegistering {
                    try await apiService.register(email: email, password: password, name: name)
                } else {
                    try await apiService.login(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            isLoading = false
        }
    }
}

// MARK: - Preview
#Preview("登入模式") {
    LoginView()
        .environment(APIService())
}

#Preview("深色模式") {
    LoginView()
        .environment(APIService())
        .preferredColorScheme(.dark)
}
