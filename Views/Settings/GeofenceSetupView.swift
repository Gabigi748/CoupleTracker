// GeofenceSetupView.swift
// CoupleTracker
//
// 地理圍欄管理頁面
// - 已設定的圍欄列表（可點擊查看詳情）
// - 新增圍欄：地址搜尋（MKLocalSearch）+ 地圖選位 + 半徑滑桿
// - 預設位置使用用戶當前位置
// - 滑動刪除
// - 接上真實 API（GET/POST/DELETE /api/geofences）

import SwiftUI
import MapKit

struct GeofenceSetupView: View {
    // MARK: - 狀態
    
    /// 圍欄列表
    @State private var zones: [GeofenceZone] = []
    
    /// 是否顯示新增圍欄 Sheet
    @State private var showAddSheet = false
    
    /// 選中查看詳情的圍欄
    @State private var selectedZone: GeofenceZone?
    
    /// 是否正在載入
    @State private var isLoading = true
    
    /// 錯誤訊息
    @State private var errorMessage: String?
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(APIService.self) private var apiService
    
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
            AddGeofenceSheet(zones: $zones, apiService: apiService)
        }
        .sheet(item: $selectedZone) { zone in
            GeofenceDetailSheet(zone: zone)
        }
        .task {
            await loadGeofences()
        }
        .refreshable {
            await loadGeofences()
        }
        .overlay {
            if isLoading {
                ProgressView("載入圍欄...")
            }
        }
    }
    
    // MARK: - 載入圍欄
    private func loadGeofences() async {
        do {
            zones = try await apiService.getGeofences()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    // MARK: - 狀態摘要
    private var summarySection: some View {
        Section {
            HStack(spacing: 12) {
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
            
            if let errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - 圍欄列表
    private var zonesSection: some View {
        Section("我的圍欄") {
            if zones.isEmpty && !isLoading {
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
                    Button {
                        selectedZone = zone
                    } label: {
                        geofenceRow(zone)
                    }
                    .tint(.primary)
                }
                .onDelete(perform: deleteZones)
            }
        }
    }
    
    /// 單一圍欄列
    private func geofenceRow(_ zone: GeofenceZone) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppTheme.softPink.opacity(0.3))
                    .frame(width: 40, height: 40)
                
                Image(systemName: zoneIcon(for: zone.name))
                    .font(.body)
                    .foregroundStyle(AppTheme.pink)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(zone.name)
                    .font(.body.bold())
                
                HStack(spacing: 8) {
                    Label("\(Int(zone.radius))m", systemImage: "circle.dashed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
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
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private func zoneIcon(for name: String) -> String {
        switch name {
        case "家": return "house.fill"
        case "公司": return "building.2.fill"
        case "學校": return "graduationcap.fill"
        default: return "mappin.circle.fill"
        }
    }
    
    private func notifyTypeText(_ zone: GeofenceZone) -> String {
        switch (zone.notifyOnEntry, zone.notifyOnExit) {
        case (true, true): return "進出通知"
        case (true, false): return "進入通知"
        case (false, true): return "離開通知"
        case (false, false): return "未啟用"
        }
    }
    
    private func deleteZones(at offsets: IndexSet) {
        let zonesToDelete = offsets.map { zones[$0] }
        
        withAnimation {
            zones.remove(atOffsets: offsets)
        }
        
        for zone in zonesToDelete {
            Task {
                do {
                    try await apiService.deleteGeofence(zone.id)
                } catch {
                    await loadGeofences()
                }
            }
        }
    }
}

// MARK: - 圍欄詳情 Sheet

struct GeofenceDetailSheet: View {
    let zone: GeofenceZone
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var cameraPosition: MapCameraPosition
    
    init(zone: GeofenceZone) {
        self.zone = zone
        _cameraPosition = State(initialValue: .region(
            MKCoordinateRegion(
                center: zone.coordinate,
                // 讓地圖範圍大約是圍欄半徑的 3 倍，方便看到整個圍欄
                latitudinalMeters: zone.radius * 3,
                longitudinalMeters: zone.radius * 3
            )
        ))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 地圖顯示圍欄位置和範圍
                Map(position: $cameraPosition) {
                    // 圍欄範圍圓圈
                    MapCircle(center: zone.coordinate, radius: zone.radius)
                        .foregroundStyle(AppTheme.pink.opacity(0.2))
                        .stroke(AppTheme.pink, lineWidth: 2)
                    
                    // Pin 標記
                    Annotation(zone.name, coordinate: zone.coordinate) {
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
                .mapStyle(.standard)
                .frame(height: 300)
                
                // 詳情資訊
                List {
                    Section("圍欄資訊") {
                        LabeledContent("名稱", value: zone.name)
                        LabeledContent("半徑", value: "\(Int(zone.radius)) 公尺")
                        LabeledContent("通知類型") {
                            Text(notifyTypeText)
                                .foregroundStyle(AppTheme.purple)
                        }
                        LabeledContent("座標") {
                            Text(String(format: "%.4f, %.4f", zone.latitude, zone.longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(zone.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.pink)
                }
            }
        }
    }
    
    private var notifyTypeText: String {
        switch (zone.notifyOnEntry, zone.notifyOnExit) {
        case (true, true): return "進出通知"
        case (true, false): return "進入通知"
        case (false, true): return "離開通知"
        case (false, false): return "未啟用"
        }
    }
}

// MARK: - 新增圍欄 Sheet

struct AddGeofenceSheet: View {
    @Binding var zones: [GeofenceZone]
    var apiService: APIService
    
    // MARK: - 表單狀態
    @State private var name = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var radius: Double = 200
    @State private var notifyOnEntry = true
    @State private var notifyOnExit = true
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasPinPlaced = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var hasInitializedCamera = false
    
    // 搜尋相關
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var showSearchResults = false
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LocationManager.self) private var locationManager
    
    enum NotifyType: String, CaseIterable {
        case both = "進入 + 離開"
        case entry = "僅進入"
        case exit = "僅離開"
    }
    
    @State private var selectedNotifyType: NotifyType = .both
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasPinPlaced && !isSaving
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 地址搜尋 + 地圖選擇位置
                    mapSection
                    
                    // 名稱輸入
                    nameSection
                    
                    // 半徑滑桿
                    radiusSection
                    
                    // 通知類型
                    notifySection
                    
                    if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
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
            .onAppear {
                initializeCameraToCurrentLocation()
            }
        }
    }
    
    // MARK: - 初始化相機到當前位置
    private func initializeCameraToCurrentLocation() {
        guard !hasInitializedCamera else { return }
        hasInitializedCamera = true
        
        if let currentLoc = locationManager.currentLocation {
            cameraPosition = .region(MKCoordinateRegion(
                center: currentLoc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        } else {
            // 沒有當前位置，預設台北
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))
        }
    }
    
    // MARK: - 地圖區域（含搜尋）
    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("選擇位置", systemImage: "mappin.circle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.purple)
            
            // 地址搜尋框
            searchBar
            
            // 搜尋結果列表
            if showSearchResults && !searchResults.isEmpty {
                searchResultsList
            }
            
            Text(hasPinPlaced ? "已選擇位置，點擊地圖可重新選擇" : "搜尋地址或點擊地圖放置圍欄中心點")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // 地圖
            ZStack {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        if hasPinPlaced, let coord = selectedCoordinate {
                            MapCircle(center: coord, radius: radius)
                                .foregroundStyle(AppTheme.pink.opacity(0.2))
                                .stroke(AppTheme.pink, lineWidth: 2)
                            
                            Annotation(
                                name.isEmpty ? "新圍欄" : name,
                                coordinate: coord
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
                        if let coordinate = proxy.convert(screenCoord, from: .local) {
                            withAnimation(.spring(duration: 0.3)) {
                                selectedCoordinate = coordinate
                                hasPinPlaced = true
                            }
                        }
                    }
                }
                
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
    
    // MARK: - 搜尋框
    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("搜尋地址或地名...", text: $searchText)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit {
                        Task { await performSearch() }
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                        showSearchResults = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark
                          ? Color(.systemGray5)
                          : Color(.systemGray6))
            )
            
            // 搜尋按鈕
            if !searchText.isEmpty {
                Button {
                    Task { await performSearch() }
                } label: {
                    if isSearching {
                        ProgressView()
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.pink)
                            .frame(width: 36, height: 36)
                    }
                }
                .disabled(isSearching)
            }
        }
    }
    
    // MARK: - 搜尋結果列表
    private var searchResultsList: some View {
        VStack(spacing: 0) {
            ForEach(searchResults.prefix(5), id: \.self) { item in
                Button {
                    selectSearchResult(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(AppTheme.pink)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "未知地點")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            
                            if let address = item.placemark.formattedAddress {
                                Text(address)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                
                if item != searchResults.prefix(5).last {
                    Divider()
                        .padding(.leading, 46)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark
                      ? Color(.systemGray5)
                      : .white)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
    }
    
    // MARK: - 搜尋邏輯
    private func performSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        isSearching = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        // 優先搜尋台灣地區
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 23.5, longitude: 121.0),
            span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
        )
        
        do {
            let search = MKLocalSearch(request: request)
            let response = try await search.start()
            searchResults = response.mapItems
            showSearchResults = true
        } catch {
            searchResults = []
        }
        
        isSearching = false
    }
    
    /// 選擇搜尋結果
    private func selectSearchResult(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        
        withAnimation(.spring(duration: 0.3)) {
            selectedCoordinate = coordinate
            hasPinPlaced = true
            
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        }
        
        // 如果名稱為空，自動填入地點名稱
        if name.isEmpty, let placeName = item.name {
            name = placeName
        }
        
        // 收起搜尋結果
        showSearchResults = false
        searchText = item.name ?? ""
    }
    
    // MARK: - 名稱輸入
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("圍欄名稱", systemImage: "tag.fill")
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.purple)
            
            HStack(spacing: 8) {
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
            Task { await saveGeofence() }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
                Text(isSaving ? "儲存中..." : "儲存圍欄")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!isFormValid)
        .opacity(isFormValid ? 1.0 : 0.5)
    }
    
    // MARK: - 儲存
    private func saveGeofence() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let coord = selectedCoordinate else { return }
        
        isSaving = true
        saveError = nil
        
        let newZone = GeofenceZone.create(
            name: trimmedName,
            latitude: coord.latitude,
            longitude: coord.longitude,
            radius: radius,
            notifyOnEntry: notifyOnEntry,
            notifyOnExit: notifyOnExit
        )
        
        do {
            let created = try await apiService.createGeofence(newZone)
            withAnimation {
                zones.append(created)
            }
            dismiss()
        } catch {
            saveError = "儲存失敗：\(error.localizedDescription)"
        }
        
        isSaving = false
    }
}

// MARK: - MKPlacemark 地址格式化

extension CLPlacemark {
    /// 格式化地址字串
    var formattedAddress: String? {
        var components: [String] = []
        if let country = country { components.append(country) }
        if let city = locality { components.append(city) }
        if let district = subLocality { components.append(district) }
        if let street = thoroughfare { components.append(street) }
        if let number = subThoroughfare { components.append(number) }
        return components.isEmpty ? nil : components.joined(separator: " ")
    }
}

// MARK: - Preview

#Preview("圍欄管理") {
    NavigationStack {
        GeofenceSetupView()
            .environment(APIService())
            .environment(LocationManager())
    }
}

#Preview("新增圍欄 Sheet") {
    AddGeofenceSheet(zones: .constant([]), apiService: APIService())
        .environment(LocationManager())
}

#Preview("深色模式") {
    NavigationStack {
        GeofenceSetupView()
            .environment(APIService())
            .environment(LocationManager())
    }
    .preferredColorScheme(.dark)
}
