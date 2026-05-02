// SettingsView.swift
// CoupleTracker
//
// 設定頁面 — 使用真實 API 資料

import SwiftUI

struct SettingsView: View {
    @Environment(APIService.self) private var apiService
    
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
    
    /// 編輯名稱
    @State private var isEditingName = false
    @State private var editedName = ""
    
    /// 錯誤訊息
    @State private var errorMessage: String?
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var userName: String {
        apiService.currentUser?.name ?? "未設定"
    }
    
    private var userEmail: String {
        apiService.currentUser?.email ?? ""
    }
    
    private var partnerName: String? {
        apiService.partnerUser?.name
    }
    
    var body: some View {
        List {
            profileSection
            pairingSection
            featureSection
            notificationSection
            accountSection
            versionSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.large)
        .alert("解除配對", isPresented: $showUnpairAlert) {
            Button("取消", role: .cancel) {}
            Button("確認解除", role: .destructive) {
                unpairPartner()
            }
        } message: {
            Text("解除配對後，將無法看到對方的位置。確定要解除嗎？")
        }
        .alert("登出", isPresented: $showLogoutAlert) {
            Button("取消", role: .cancel) {}
            Button("確認登出", role: .destructive) {
                apiService.logout()
            }
        } message: {
            Text("登出後需要重新登入才能使用。")
        }
        .alert("修改名稱", isPresented: $isEditingName) {
            TextField("輸入新名稱", text: $editedName)
            Button("取消", role: .cancel) {}
            Button("確認") {
                updateName()
            }
        } message: {
            Text("輸入你想顯示的名稱")
        }
        .alert("錯誤", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好的") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    // MARK: - 個人資料區塊
    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AppTheme.softGradient)
                        .frame(width: 64, height: 64)
                    
                    Text(String(userName.prefix(1)))
                        .font(.title.bold())
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(userName)
                        .font(.title3.bold())
                    
                    Text(userEmail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    editedName = userName
                    isEditingName = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.pink)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - 配對狀態
    private var pairingSection: some View {
        Section("配對狀態") {
            HStack(spacing: 12) {
                Image(systemName: partnerName != nil ? "heart.fill" : "heart.slash")
                    .font(.title3)
                    .foregroundStyle(partnerName != nil ? AppTheme.pink : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    if let partner = partnerName {
                        Text("已與 \(partner) 配對")
                            .font(.body)
                        Text("位置共享中")
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
            
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("高精度定位")
                        Text(isHighAccuracy ? "精確模式（較耗電）" : "省電模式（精度較低）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "location.circle.fill")
                        .foregroundStyle(AppTheme.blue)
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
            HStack {
                Label {
                    Text("圍欄進出通知")
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(AppTheme.orange)
                }
                
                Spacer()
                
                Toggle("", isOn: $geofenceNotification)
                    .tint(AppTheme.pink)
                    .labelsHidden()
            }
            
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
                    Text("小寧和魚魚")
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
    
    private func unpairPartner() {
        Task {
            do {
                try await apiService.unpair()
            } catch {
                errorMessage = "解除配對失敗：\(error.localizedDescription)"
            }
        }
    }
    
    private func updateName() {
        let newName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        Task {
            do {
                try await apiService.updateProfile(name: newName)
            } catch {
                errorMessage = "修改名稱失敗：\(error.localizedDescription)"
            }
        }
    }
}
