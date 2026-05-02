// GeofenceSetupView.swift
// CoupleTracker
//
// 地理圍欄管理頁面
// - 已設定的圍欄列表（名稱、半徑、通知類型）
// - 新增圍欄按鈕（sheet 呈現表單）
// - 新增時：地圖選位、半徑滑桿、名稱輸入、通知類型選擇
// - 滑動刪除已有圍欄

import SwiftUI
import MapKit

struct GeofenceSetupView: View {
    // MARK: - 假資料狀態
    
    /// 圍欄列表
    @State private var zones: [GeofenceZone] = [
        GeofenceZone.create(
            name: "家",
            latitude: 25.0330,
            longitude: 121.5654,
            radius: 200,
            notifyOnEntry: true,
            notifyOnExit: true
        ),
        GeofenceZone.create(
            name: "公司",
            latitude: 25.0478,
            longitude: 121.5170,
            radius: 300,
            notifyOnEntry: true,
            notifyOnExit: false
        ),
        GeofenceZone.create(
            name: "學校",
            latitude: 25.0145,
            longitude: 121.5319,
            radius: 150,
            notifyOnEntry: false,
            notifyOnExit: true
        ),
    ]
    
    /// 是否顯示新增圍欄 Sheet
    @State private var showAddSheet = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    /// 剩餘可用數量
    private var remainingSlots: Int {
        max(0, GeofenceZone.maxGeofences - zones.count)
    }
    
    var body: some View {
        List {
            // 狀態摘要
            summarySection
            
            // 圍欄列表
            zonesSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("地理圍欄")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(AppTheme.pink)
                }
                .disabled(remainingSlots <= 0)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddGeofenceSheet(zones: $zones)
        }
    }
    
    // MARK: - 狀態摘要
    private var summarySection: some View {
        Section {
            HStack(spacing: 12) {
                // 圍欄圖示
                ZStack {
                    Circle()
                        .fill(AppTheme.softGradient)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("已設定 \(zones.count) 個圍欄")
                        .font(.headline)
                    
                    Text("還可新增 \(remainingSlots) 個（上限 \(GeofenceZone.maxGeofences) 個）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - 圍欄列表
    private var zonesSection: some View {
        Section("我的圍欄") {
            if zones.isEmpty {
                // 空狀態
                VStack(spacing: 12) {
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    
                    Text("尚未設定任何圍欄")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        showAddSheet = true
                    } label: {
                        Text("新增第一個圍欄")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(AppTheme.primaryGradient)
                            )
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(zones) { zone in
                    geofenceRow(zone)
                }
                .onDelete(perform: deleteZones)
            }
        }
    }
    
    /// 單一圍欄列
    private func geofenceRow(_ zone: GeofenceZone) -> some View {
        HStack(spacing: 12) {
            // 圍欄圖示
            ZStack {
                Circle()
                    .fill(AppTheme.softPink.opacity(0.3))
                    .frame(width: 40, height: 40)
                
                Image(systemName: zoneIcon(for: zone.name))
                    .font(.body)
                    .foregroundStyle(AppTheme.pink)
            }
            
            // 圍欄資訊
            VStack(alignment: .leading, spacing: 4) {
                Text(zone.name)
                    .font(.body.bold())
                
                HStack(spacing: 8) {
                    // 半徑
                    Label("\(Int(zone.radius))m", systemImage: "circle.dashed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // 通知類型
                    Text(notifyTypeText(zone))
                        .font(.caption)
                        .foregroundStyle(AppTheme.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(AppTheme.purple.opacity(0.1))
                        )
                }
            }
            
            Spacer()
            
            // 狀態指示
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.green)
        }
        .padding(.vertical, 4)
    }
    
    /// 根據名稱回傳對應圖示
    private func zoneIcon(for name: String) -> String {
        switch name {
        case "家": return "house.fill"
        case "公司": return "building.2.fill"
        case "學校": return "graduationcap.fill"
        default: return "mappin.circle.fill"
        }
    }
    
    /// 通知類型文字
    private func notifyTypeText(_ zone: GeofenceZone) -> String {
        switch (zone.notifyOnEntry, zone.notifyOnExit) {
        case (true, true): return "進出通知"
        case (true, false): return "進入通知"
        case (false, true): return "離開通知"
        case (false, false): return "未啟用"
        }
    }
    
    /// 滑動刪除
    private func deleteZones(at offsets: IndexSet) {
        // TODO: 呼叫 GeofenceManager 刪除
        withAnimation {
            zones.remove(atOffsets: offsets)
        }
    }
}

// MARK: - 新增圍欄 Sheet

struct AddGeofenceSheet: View {
    /// 綁定外部圍欄列表
    @Binding var zones: [GeofenceZone]
    
    // MARK: - 表單狀態
    
    /// 圍欄名稱
    @State private var name = ""
    
    /// 選擇的座標
    @State private var selectedCoordinate = CLLocationCoordinate2D(
        latitude: 25.0330,
        longitude: 121.5654
    )
    
    /// 圍欄半徑（公尺）
    @State private var radius: Double = 200
    
    /// 進入時通知
    @State private var notifyOnEntry = true
    
    /// 離開時通知
    @State private var notifyOnExit = true
    
    /// 地圖相機位置
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
    )
    
    /// 是否已放置 Pin
    @State private var hasPinPlaced = false
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    /// 通知類型選項
    enum NotifyType: String, CaseIterable {
        case both = "進入 + 離開"
        case entry = "僅進入"
        case exit = "僅離開"
    }
    
    @State private var selectedNotifyType: NotifyType = .both
    
    /// 表單是否有效
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasPinPlaced
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 地圖選擇位置
                    mapSection
                    
                    // 名稱輸入
                    nameSection
                    
                    // 半徑滑桿
                    radiusSection
                    
                    // 通知類型
                    notifySection
                    
                    // 儲存按鈕
                    saveButton
                }
                .padding(16)
            }
            .navigationTitle("新增圍欄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.pink)
                }
            }
        }
    }
    
    // MARK: - 地圖區域
    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("選擇位置", systemImage: "mappin.circle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.purple)
            
            Text("點擊地圖放置圍欄中心點")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // 地圖
            ZStack {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        // 已放置的 Pin
                        if hasPinPlaced {
                            // 圍欄範圍圓圈
                            MapCircle(
                                center: selectedCoordinate,
                                radius: radius
                            )
                            .foregroundStyle(AppTheme.pink.opacity(0.2))
                            .stroke(AppTheme.pink, lineWidth: 2)
                            
                            // Pin 標記
                            Annotation(
                                name.isEmpty ? "新圍欄" : name,
                                coordinate: selectedCoordinate
                            ) {
                                VStack(spacing: 0) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title)
                                        .foregroundStyle(AppTheme.pink)
                                    
                                    Image(systemName: "triangle.fill")
                                        .font(.system(size: 6))
                                        .foregroundStyle(AppTheme.pink)
                                        .rotationEffect(.degrees(180))
                                        .offset(y: -3)
                                }
                            }
                        }
                    }
                    .mapStyle(.standard)
                    .onTapGesture { screenCoord in
                        // 點擊地圖放置 Pin
                        if let coordinate = proxy.convert(screenCoord, from: .local) {
                            withAnimation(.spring(duration: 0.3)) {
                                selectedCoordinate = coordinate
                                hasPinPlaced = true
                            }
                        }
                    }
                }
                
                // 未放置 Pin 時的提示
                if !hasPinPlaced {
                    VStack {
                        Spacer()
                        Text("👆 點擊地圖選擇位置")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(.black.opacity(0.6))
                            )
                            .padding(.bottom, 12)
                    }
                }
            }
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius))
            .shadow(color: AppTheme.pink.opacity(0.1), radius: 8, y: 4)
        }
    }
    
    // MARK: - 名稱輸入
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("圍欄名稱", systemImage: "tag.fill")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.purple)
            
            HStack(spacing: 8) {
                // 快速選擇常用名稱
                ForEach(["家", "公司", "學校"], id: \.self) { preset in
                    Button {
                        name = preset
                    } label: {
                        Text(preset)
                            .font(.caption.bold())
                            .foregroundStyle(name == preset ? .white : AppTheme.pink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(name == preset
                                          ? AnyShapeStyle(AppTheme.primaryGradient)
                                          : AnyShapeStyle(AppTheme.pink.opacity(0.1)))
                            )
                    }
                }
            }
            
            TextField("輸入自訂名稱...", text: $name)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.smallRadius)
                        .fill(colorScheme == .dark
                              ? Color(.systemGray5)
                              : Color(.systemGray6))
                )
        }
    }
    
    // MARK: - 半徑滑桿
    private var radiusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("圍欄半徑", systemImage: "circle.dashed")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.purple)
                
                Spacer()
                
                Text("\(Int(radius)) 公尺")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.pink)
            }
            
            Slider(value: $radius, in: 100...1000, step: 50) {
                Text("半徑")
            } minimumValueLabel: {
                Text("100m")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("1km")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .tint(AppTheme.pink)
        }
        .cardStyle()
    }
    
    // MARK: - 通知類型
    private var notifySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("通知類型", systemImage: "bell.badge.fill")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.purple)
            
            Picker("通知類型", selection: $selectedNotifyType) {
                ForEach(NotifyType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedNotifyType) { _, newValue in
                switch newValue {
                case .both:
                    notifyOnEntry = true
                    notifyOnExit = true
                case .entry:
                    notifyOnEntry = true
                    notifyOnExit = false
                case .exit:
                    notifyOnEntry = false
                    notifyOnExit = true
                }
            }
            
            // 說明文字
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                
                Text(notifyDescription)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .cardStyle()
    }
    
    /// 通知說明文字
    private var notifyDescription: String {
        switch selectedNotifyType {
        case .both: return "對方進入或離開此區域時都會通知你"
        case .entry: return "對方進入此區域時通知你"
        case .exit: return "對方離開此區域時通知你"
        }
    }
    
    // MARK: - 儲存按鈕
    private var saveButton: some View {
        Button {
            saveGeofence()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text("儲存圍欄")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!isFormValid)
        .opacity(isFormValid ? 1.0 : 0.5)
    }
    
    // MARK: - 儲存
    private func saveGeofence() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        let newZone = GeofenceZone.create(
            name: trimmedName,
            latitude: selectedCoordinate.latitude,
            longitude: selectedCoordinate.longitude,
            radius: radius,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit
        )
        
        // TODO: 呼叫 GeofenceManager 新增到 Firestore
        withAnimation {
            zones.append(newZone)
        }
        
        dismiss()
    }
}

// MARK: - Preview

#Preview("圍欄管理") {
    NavigationStack {
        GeofenceSetupView()
    }
}

#Preview("新增圍欄 Sheet") {
    AddGeofenceSheet(zones: .constant([]))
}

#Preview("深色模式") {
    NavigationStack {
        GeofenceSetupView()
    }
    .preferredColorScheme(.dark)
}
