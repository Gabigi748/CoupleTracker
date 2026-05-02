// LocationHistoryView.swift
// CoupleTracker
//
// 位置歷史頁面
// - 日期選擇器
// - 地圖上顯示軌跡（MapPolyline）
// - 時間軸列表（時間 + 地址）

import SwiftUI
import MapKit

// MARK: - 歷史位置資料模型（假資料用）
struct HistoryLocation: Identifiable {
    let id = UUID()
    let time: Date
    let coordinate: CLLocationCoordinate2D
    let address: String
}

struct LocationHistoryView: View {
    // MARK: - 狀態
    @State private var selectedDate = Date()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showingPartnerHistory = false  // 切換看自己/對方
    
    @Environment(\.colorScheme) private var colorScheme
    
    // 假資料：歷史位置點
    @State private var historyLocations: [HistoryLocation] = [
        HistoryLocation(
            time: Calendar.current.date(bySettingHour: 8, minute: 30, second: 0, of: Date()) ?? Date(),
            coordinate: CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
            address: "台北市信義區信義路五段7號"
        ),
        HistoryLocation(
            time: Calendar.current.date(bySettingHour: 10, minute: 15, second: 0, of: Date()) ?? Date(),
            coordinate: CLLocationCoordinate2D(latitude: 25.0418, longitude: 121.5449),
            address: "台北市大安區忠孝東路四段"
        ),
        HistoryLocation(
            time: Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date(),
            coordinate: CLLocationCoordinate2D(latitude: 25.0478, longitude: 121.5170),
            address: "台北市中正區北平西路3號"
        ),
        HistoryLocation(
            time: Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: Date()) ?? Date(),
            coordinate: CLLocationCoordinate2D(latitude: 25.0375, longitude: 121.5637),
            address: "台北市信義區松壽路12號"
        ),
        HistoryLocation(
            time: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date(),
            coordinate: CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654),
            address: "台北市信義區信義路五段7號"
        ),
    ]
    
    // 軌跡座標（用於 MapPolyline）
    private var routeCoordinates: [CLLocationCoordinate2D] {
        historyLocations.map(\.coordinate)
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
            
            // 時間軸列表（下半部）
            timelineList
        }
        .navigationTitle("位置歷史")
        .navigationBarTitleDisplayMode(.inline)
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
                Text("寶貝的軌跡").tag(true)
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
            MapPolyline(coordinates: routeCoordinates)
                .stroke(
                    showingPartnerHistory
                        ? AppTheme.pink
                        : .blue,
                    lineWidth: 4
                )
            
            // 各個位置點標記
            ForEach(Array(historyLocations.enumerated()), id: \.element.id) { index, location in
                Annotation(
                    timeFormatter.string(from: location.time),
                    coordinate: location.coordinate
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
    
    // MARK: - 時間軸列表
    private var timelineList: some View {
        List {
            ForEach(Array(historyLocations.enumerated()), id: \.element.id) { index, location in
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
                        if index < historyLocations.count - 1 {
                            Rectangle()
                                .fill(AppTheme.softPink)
                                .frame(width: 2, height: 20)
                        } else {
                            Spacer().frame(height: 20)
                        }
                    }
                    
                    // 時間
                    Text(timeFormatter.string(from: location.time))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.purple)
                        .frame(width: 50, alignment: .leading)
                    
                    // 地址
                    VStack(alignment: .leading, spacing: 4) {
                        Text(location.address)
                            .font(.subheadline)
                            .lineLimit(2)
                        
                        // 停留時間（假資料）
                        if index < historyLocations.count - 1 {
                            let nextTime = historyLocations[index + 1].time
                            let duration = nextTime.timeIntervalSince(location.time)
                            let minutes = Int(duration / 60)
                            Text("停留 \(minutes) 分鐘")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    // 定位按鈕
                    Button {
                        withAnimation {
                            cameraPosition = .region(MKCoordinateRegion(
                                center: location.coordinate,
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
}

// MARK: - Preview
#Preview("位置歷史") {
    NavigationStack {
        LocationHistoryView()
    }
}

#Preview("深色模式") {
    NavigationStack {
        LocationHistoryView()
    }
    .preferredColorScheme(.dark)
}
