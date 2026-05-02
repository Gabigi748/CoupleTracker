// SettingsView.swift
// CoupleTracker
//
// 設定頁面
// - 個人資料區塊（頭像、名字、email）
// - 配對狀態（顯示對方名字，或「未配對」）
// - 功能列表：圍欄管理、定位精度、通知設定
// - 解除配對 / 登出（帶確認 alert）
// - 底部 App 版本

import SwiftUI

struct SettingsView: View {
    // MARK: - 假資料狀態
    
    /// 用戶名稱
    @State private var userName = "小魚"
    
    /// 用戶 Email
    @State private var userEmail = "fish@example.com"
    
    /// 配對對象名稱（nil 表示未配對）
    @State private var partnerName: String? = "寶貝"
    
    /// 高精度定位模式
    @State private var isHighAccuracy = true
    
    /// 圍欄通知開關
    @State private var geofenceNotification = true
    
    /// SOS 通知開關
    @State private var sosNotification = true
    
    /// 顯示解除配對確認
    @State private var showUnpairAlert = false
    
    /// 顯示登出確認
    @State private var showLogoutAlert = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        List {
            // 個人資料區塊
            profileSection
            
            // 配對狀態
            pairingSection
            
            // 功能設定
            featureSection
            
            // 通知設定
            notificationSection
            
            // 帳號操作
            accountSection
            
            // App 版本
            versionSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.large)
        // 解除配對確認 Alert
        .alert("解除配對", isPresented: $showUnpairAlert) {
            Button("取消", role: .cancel) {}
            Button("確認解除", role: .destructive) {
                unpairPartner()
            }
        } message: {
            Text("解除配對後，將無法看到對方的位置。確定要解除嗎？")
        }
        // 登出確認 Alert
        .alert("登出", isPresented: $showLogoutAlert) {
            Button("取消", role: .cancel) {}
            Button("確認登出", role: .destructive) {
                logout()
            }
        } message: {
            Text("登出後需要重新登入才能使用。")
        }
    }
    
    // MARK: - 個人資料區塊
    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                // 頭像
                ZStack {
                    Circle()
                        .fill(AppTheme.softGradient)
                        .frame(width: 64, height: 64)
                    
                    Text(String(userName.prefix(1)))
                        .font(.title.bold())
                        .foregroundStyle(.white)
                }
                
                // 名字 + Email
                VStack(alignment: .leading, spacing: 4) {
                    Text(userName)
                        .font(.title3.bold())
                    
                    Text(userEmail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // 編輯按鈕
                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.pink)
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - 配對狀態
    private var pairingSection: some View {
        Section("配對狀態") {
            HStack(spacing: 12) {
                // 配對圖示
                Image(systemName: partnerName != nil ? "heart.fill" : "heart.slash")
                    .font(.title3)
                    .foregroundStyle(partnerName != nil ? AppTheme.pink : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    if let partner = partnerName {
                        Text("已與 \(partner) 配對")
                            .font(.body)
                        Text("位置共享中 💕")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("未配對")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Text("前往配對頁面邀請你的另一半")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // 配對狀態指示燈
                Circle()
                    .fill(partnerName != nil ? .green : .gray)
                    .frame(width: 10, height: 10)
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - 功能設定
    private var featureSection: some View {
        Section("功能設定") {
            // 地理圍欄管理
            NavigationLink {
                GeofenceSetupView()
            } label: {
                Label {
                    Text("地理圍欄管理")
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(AppTheme.purple)
                }
            }
            
            // 定位精度設定
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("高精度定位")
                        Text(isHighAccuracy ? "精確模式（較耗電）" : "省電模式（精度較低）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: isHighAccuracy ? "location.fill" : "location")
                        .foregroundStyle(isHighAccuracy ? AppTheme.pink : .secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $isHighAccuracy)
                    .tint(AppTheme.pink)
                    .labelsHidden()
            }
        }
    }
    
    // MARK: - 通知設定
    private var notificationSection: some View {
        Section("通知設定") {
            // 圍欄通知
            HStack {
                Label {
                    Text("圍欄進出通知")
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(AppTheme.purple)
                }
                
                Spacer()
                
                Toggle("", isOn: $geofenceNotification)
                    .tint(AppTheme.pink)
                    .labelsHidden()
            }
            
            // SOS 通知
            HStack {
                Label {
                    Text("SOS 緊急通知")
                } icon: {
                    Image(systemName: "sos.circle.fill")
                        .foregroundStyle(AppTheme.sosRed)
                }
                
                Spacer()
                
                Toggle("", isOn: $sosNotification)
                    .tint(AppTheme.pink)
                    .labelsHidden()
            }
        }
    }
    
    // MARK: - 帳號操作
    private var accountSection: some View {
        Section {
            // 解除配對
            if partnerName != nil {
                Button(role: .destructive) {
                    showUnpairAlert = true
                } label: {
                    Label {
                        Text("解除配對")
                    } icon: {
                        Image(systemName: "heart.slash.fill")
                    }
                }
            }
            
            // 登出
            Button(role: .destructive) {
                showLogoutAlert = true
            } label: {
                Label {
                    Text("登出")
                } icon: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }
    
    // MARK: - App 版本
    private var versionSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Text("CoupleTracker")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("版本 1.0.0 (1)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }
    
    // MARK: - 動作
    
    /// 解除配對
    private func unpairPartner() {
        // TODO: 呼叫 APIService 解除配對
        withAnimation {
            partnerName = nil
        }
    }
    
    /// 登出
    private func logout() {
        // TODO: 呼叫 APIService 登出
    }
}

// MARK: - Preview

#Preview("設定頁面") {
    NavigationStack {
        SettingsView()
    }
}

#Preview("未配對狀態") {
    NavigationStack {
        SettingsView()
    }
}

#Preview("深色模式") {
    NavigationStack {
        SettingsView()
    }
    .preferredColorScheme(.dark)
}
