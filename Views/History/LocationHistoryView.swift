// LocationHistoryView.swift
// CoupleTracker
//
// 位置歷史頁面
// - 日期選擇器
// - 地圖上顯示軌跡（MapPolyline）
// - 時間軸列表（時間 + 地址，地址 lazy load）
// - 支援查看自己或配對對象的歷史
// - GCJ-02 座標轉換（中國設備）

import SwiftUI
import MapKit
import CoreLocation

// MARK: - 載入狀態

/// 位置歷史載入狀態
private enum LoadingState {
    case idle
    case loading
    case loaded
    case error(String)
}

struct LocationHistoryView: View {
    // MARK: - 環境
    @Environment(APIService.self) private var apiService
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - 狀態
    @State private var selectedDate = Date()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showingPartnerHistory = false
    @State private var loadingState: LoadingState = .idle
    
    /// 位置歷史點（從 API 載入）
    @State private var historyPoints: [LocationHistoryPoint] = []
    
    /// 地址快取（key: LocationHistoryPoint.id）
    @State private var addressCache: [Int: String] = [:]
    
    /// 反向地理編碼任務追蹤
    @State private var geocodingTask: Task<Void, Never>?
    
    // 軌跡座標（用於 MapPolyline）
    private var routeCoordinates: [CLLocationCoordinate2D] {
        historyPoints.map(\.coordinate)
    }
    
    // 時間格式化
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh-Hant")
        f.dateFormat = "HH:mm"
        return f
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // 日期選擇 + 切換
            headerSection
            
            // 地圖（上半部）
            mapSection
                .frame(height: 300)
            
            // 內容區域（下半部）
            contentSection
        }
        .navigationTitle("位置歷史")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadHistory()
        }
        .onChange(of: selectedDate) { _, _ in
            Task { await loadHistory() }
        }
        .onChange(of: showingPartnerHistory) { _, _ in
            Task { await loadHistory() }
        }
    }
    
    // MARK: - 頂部：日期選擇 + 人物切換
    private var headerSection: some View {
        VStack(spacing: 12) {
            // 日期選擇器
            DatePicker(
                "選擇日期",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .environment(\.locale, Locale(identifier: "zh-Hant"))
            .tint(AppTheme.pink)
            
            // 切換自己/對方
            Picker("查看對象", selection: $showingPartnerHistory) {
                Text("我的軌跡").tag(false)
                Text("對方的軌跡").tag(true)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color(.systemGray6) : .white)
    }
    
    // MARK: - 地圖區域
    private var mapSection: some View {
        Map(position: $cameraPosition) {
            // 軌跡線
            if routeCoordinates.count >= 2 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(
                        showingPartnerHistory
                            ? AppTheme.pink
                            : .blue,
                        lineWidth: 4
                    )
            }
            
            // 各個位置點標記
            ForEach(Array(historyPoints.enumerated()), id: \.element.id) { index, point in
                Annotation(
                    timeFormatter.string(from: point.date),
                    coordinate: point.coordinate
                ) {
                    ZStack {
                        Circle()
                            .fill(showingPartnerHistory ? AppTheme.pink : .blue)
                            .frame(width: 24, height: 24)
                        
                        Text("\(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .mapStyle(.standard)
    }
    
    // MARK: - 內容區域（根據狀態顯示）
    @ViewBuilder
    private var contentSection: some View {
        switch loadingState {
        case .idle:
            emptyStateView(message: "選擇日期查看位置歷史")
            
        case .loading:
            VStack(spacing: 16) {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Text("載入中...")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            
        case .loaded:
            if historyPoints.isEmpty {
                emptyStateView(message: showingPartnerHistory
                    ? "對方這天沒有位置記錄"
                    : "你這天沒有位置記錄")
            } else {
                timelineList
            }
            
        case .error(let message):
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("重試") {
                    Task { await loadHistory() }
                }
                .tint(AppTheme.pink)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - 空狀態
    private func emptyStateView(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "mappin.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 時間軸列表
    private var timelineList: some View {
        List {
            ForEach(Array(historyPoints.enumerated()), id: \.element.id) { index, point in
                HStack(spacing: 16) {
                    // 時間軸左側
                    VStack(spacing: 0) {
                        // 上方連接線
                        if index > 0 {
                            Rectangle()
                                .fill(AppTheme.softPink)
                                .frame(width: 2, height: 20)
                        } else {
                            Spacer().frame(height: 20)
                        }
                        
                        // 圓點
                        Circle()
                            .fill(showingPartnerHistory
                                  ? AppTheme.pink
                                  : .blue)
                            .frame(width: 12, height: 12)
                        
                        // 下方連接線
                        if index < historyPoints.count - 1 {
                            Rectangle()
                                .fill(AppTheme.softPink)
                                .frame(width: 2, height: 20)
                        } else {
                            Spacer().frame(height: 20)
                        }
                    }
                    
                    // 時間
                    Text(timeFormatter.string(from: point.date))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.purple)
                        .frame(width: 50, alignment: .leading)
                    
                    // 地址 / 座標
                    VStack(alignment: .leading, spacing: 4) {
                        if let address = addressCache[point.id] {
                            Text(address)
                                .font(.subheadline)
                                .lineLimit(2)
                        } else {
                            Text(String(format: "%.4f, %.4f", point.lat, point.lng))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        // 停留時間
                        if index < historyPoints.count - 1 {
                            let nextTime = historyPoints[index + 1].date
                            let duration = nextTime.timeIntervalSince(point.date)
                            let minutes = Int(duration / 60)
                            if minutes > 0 {
                                Text("停留 \(minutes) 分鐘")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        // 電量與精度資訊
                        HStack(spacing: 8) {
                            if let battery = point.battery, battery >= 0 {
                                Label("\(battery)%", systemImage: "battery.50percent")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let accuracy = point.accuracy {
                                Label("±\(Int(accuracy))m", systemImage: "location.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // 定位按鈕
                    Button {
                        withAnimation {
                            cameraPosition = .region(MKCoordinateRegion(
                                center: point.coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                            ))
                        }
                    } label: {
                        Image(systemName: "location.circle")
                            .foregroundStyle(AppTheme.pink)
                    }
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }
    
    // MARK: - 資料載入
    
    /// 載入位置歷史
    private func loadHistory() async {
        // 取消之前的地理編碼任務
        geocodingTask?.cancel()
        
        loadingState = .loading
        addressCache = [:]
        
        // 計算選擇日期的 00:00 ~ 23:59:59（UTC+8 → UTC）
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)?.addingTimeInterval(-1) else {
            loadingState = .error("日期計算錯誤")
            return
        }
        
        // 決定查詢的 userId
        let userId: String?
        if showingPartnerHistory {
            userId = apiService.partnerUser?.uid
        } else {
            userId = nil  // nil = 查自己
        }
        
        do {
            let points = try await apiService.getLocationHistory(
                userId: userId,
                start: startOfDay,
                end: endOfDay,
                limit: 500
            )
            
            // 按時間正序排列（最早的在前）
            historyPoints = points.sorted { $0.date < $1.date }
            loadingState = .loaded
            
            // 調整地圖視角
            fitMapToRoute()
            
            // 背景 lazy load 地址
            startGeocoding()
            
        } catch {
            historyPoints = []
            loadingState = .error(error.localizedDescription)
        }
    }
    
    /// 調整地圖視角以顯示整條軌跡
    private func fitMapToRoute() {
        guard !routeCoordinates.isEmpty else {
            cameraPosition = .automatic
            return
        }
        
        if routeCoordinates.count == 1 {
            // 只有一個點，直接定位
            cameraPosition = .region(MKCoordinateRegion(
                center: routeCoordinates[0],
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
            return
        }
        
        // 計算包含所有點的區域
        var minLat = routeCoordinates[0].latitude
        var maxLat = routeCoordinates[0].latitude
        var minLng = routeCoordinates[0].longitude
        var maxLng = routeCoordinates[0].longitude
        
        for coord in routeCoordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLng = min(minLng, coord.longitude)
            maxLng = max(maxLng, coord.longitude)
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.005),
            longitudeDelta: max((maxLng - minLng) * 1.3, 0.005)
        )
        
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
    
    // MARK: - 反向地理編碼（Lazy Load）
    
    /// 開始背景地理編碼
    private func startGeocoding() {
        geocodingTask = Task {
            let geocoder = CLGeocoder()
            
            for point in historyPoints {
                // 檢查是否已取消
                guard !Task.isCancelled else { return }
                
                // 跳過已有地址的點
                guard addressCache[point.id] == nil else { continue }
                
                // CLGeocoder 有速率限制，每次間隔一小段時間
                do {
                    let placemarks = try await geocoder.reverseGeocodeLocation(point.clLocation)
                    if let placemark = placemarks.first {
                        let address = formatAddress(placemark)
                        if !Task.isCancelled {
                            addressCache[point.id] = address
                        }
                    }
                } catch {
                    // 地理編碼失敗（可能是速率限制），等久一點再試
                    try? await Task.sleep(for: .seconds(1))
                }
                
                // 間隔 0.3 秒避免觸發 Apple 的速率限制
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
    
    /// 格式化地址
    private func formatAddress(_ placemark: CLPlacemark) -> String {
        var components: [String] = []
        if let city = placemark.locality { components.append(city) }
        if let district = placemark.subLocality { components.append(district) }
        if let street = placemark.thoroughfare { components.append(street) }
        if let number = placemark.subThoroughfare { components.append(number) }
        
        if components.isEmpty {
            if let name = placemark.name { return name }
            return "未知地點"
        }
        return components.joined(separator: "")
    }
}

// MARK: - Preview
#Preview("位置歷史") {
    NavigationStack {
        LocationHistoryView()
    }
    .environment(APIService())
}

#Preview("深色模式") {
    NavigationStack {
        LocationHistoryView()
    }
    .environment(APIService())
    .preferredColorScheme(.dark)
}
