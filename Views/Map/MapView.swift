// MapView.swift
// CoupleTracker
//
// 主地圖頁面（App 最核心的頁面）
// - SwiftUI Map（MapKit, iOS 17+）
// - 顯示自己位置（藍色標記 + 精度圈）與對方位置（粉色愛心）
// - 頂部距離資訊、底部對方電量
// - 地圖樣式切換（標準/衛星）
// - 一鍵定位到自己/對方
// - 透過 WebSocketManager 接收對方即時位置

import SwiftUI
import MapKit

// MARK: - 地圖樣式列舉
enum MapStyleOption: String, CaseIterable {
    case standard = "標準"
    case satellite = "衛星"
    case hybrid = "混合"
}

struct MapView: View {
    // MARK: - 狀態
    
    // 地圖相機位置
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    // 地圖樣式
    @State private var selectedMapStyle: MapStyleOption = .standard
    @State private var showStylePicker = false
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(LocationManager.self) private var locationManager
    @Environment(WebSocketManager.self) private var webSocketManager
    @Environment(APIService.self) private var apiService
    
    // 自己的位置座標
    private var myLocation: CLLocationCoordinate2D? {
        locationManager.currentLocation?.coordinate
    }
    
    // 自己的定位精度（公尺）
    private var myAccuracy: Double {
        locationManager.currentAccuracy ?? 0
    }
    
    // 對方的位置座標
    private var partnerLocation: CLLocationCoordinate2D? {
        webSocketManager.partnerLocation?.coordinate
    }
    
    // 對方名稱
    private var partnerName: String {
        apiService.partnerUser?.name ?? "對方"
    }
    
    // 對方電量
    private var partnerBattery: Int {
        webSocketManager.partnerBattery ?? apiService.partnerUser?.batteryLevel ?? -1
    }
    
    // 最後更新時間
    private var lastUpdated: Date? {
        webSocketManager.partnerLocation?.timestamp
    }
    
    // 計算距離（公里）
    private var distanceText: String {
        guard let myLoc = myLocation, let partnerLoc = partnerLocation else {
            return "--"
        }
        let my = CLLocation(latitude: myLoc.latitude, longitude: myLoc.longitude)
        let partner = CLLocation(latitude: partnerLoc.latitude, longitude: partnerLoc.longitude)
        let distance = my.distance(from: partner)
        
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
    
    // 最後更新時間文字
    private var lastUpdatedText: String {
        guard let lastUpdated else { return "等待更新..." }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh-Hant")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastUpdated, relativeTo: .now)
    }
    
    // 精度文字
    private var accuracyText: String {
        guard myAccuracy > 0 else { return "" }
        return "±\(Int(myAccuracy))m"
    }
    
    // 精度顏色
    private var accuracyColor: Color {
        if myAccuracy <= 10 { return .green }
        if myAccuracy <= 30 { return .orange }
        return .red
    }
    
    // 地圖樣式
    private var mapStyle: MapStyle {
        switch selectedMapStyle {
        case .standard: return .standard
        case .satellite: return .imagery
        case .hybrid: return .hybrid
        }
    }
    
    var body: some View {
        ZStack {
            // 地圖本體
            mapContent
            
            // 上方資訊列
            VStack {
                topInfoBar
                Spacer()
                bottomInfoBar
            }
            
            // 右側控制按鈕
            VStack {
                Spacer()
                controlButtons
                    .padding(.bottom, 100)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 16)
        }
    }
    
    // MARK: - 地圖內容
    private var mapContent: some View {
        Map(position: $cameraPosition) {
            // 自己的精度圈（半透明藍色圓圈）
            if let myLoc = myLocation, myAccuracy > 0 {
                MapCircle(center: myLoc, radius: myAccuracy)
                    .foregroundStyle(.blue.opacity(0.1))
                    .stroke(.blue.opacity(0.3), lineWidth: 1)
            }
            
            // 自己的位置標記（藍色圓點）
            if let myLoc = myLocation {
                Annotation("我", coordinate: myLoc) {
                    ZStack {
                        Circle()
                            .fill(.blue.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Circle()
                            .fill(.blue)
                            .frame(width: 16, height: 16)
                        Circle()
                            .stroke(.white, lineWidth: 3)
                            .frame(width: 16, height: 16)
                    }
                }
            }
            
            // 對方的位置標記（粉色愛心 + 移動狀態）
            if let partnerLoc = partnerLocation {
                Annotation(partnerName, coordinate: partnerLoc) {
                    VStack(spacing: 2) {
                        // 名字標籤
                        HStack(spacing: 4) {
                            // 移動狀態圖示
                            if let activity = MotionActivity(rawValue: webSocketManager.partnerActivity),
                               activity != .unknown {
                                Image(systemName: activity.iconName)
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                            }
                            Text(partnerName)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(AppTheme.pink)
                        )
                        
                        // 愛心圖示
                        Image(systemName: "heart.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(AppTheme.pink)
                            .shadow(color: AppTheme.pink.opacity(0.5), radius: 4, y: 2)
                        
                        // 三角形指標
                        Image(systemName: "triangle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(AppTheme.pink)
                            .rotationEffect(.degrees(180))
                            .offset(y: -4)
                    }
                }
            }
        }
        .mapStyle(mapStyle)
        .mapControls {
            // 隱藏預設控制項，使用自訂按鈕
        }
    }
    
    // MARK: - 頂部資訊列
    private var topInfoBar: some View {
        HStack(spacing: 12) {
            // 愛心圖示
            Image(systemName: "heart.fill")
                .foregroundStyle(AppTheme.pink)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("距離 \(distanceText)")
                    .font(.headline)
                
                HStack(spacing: 6) {
                    Text("更新於\(lastUpdatedText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // 精度指示
                    if !accuracyText.isEmpty {
                        Text(accuracyText)
                            .font(.caption2.bold())
                            .foregroundStyle(accuracyColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(accuracyColor.opacity(0.15))
                            )
                    }
                }
            }
            
            Spacer()
            
            // 地圖樣式切換
            Menu {
                ForEach(MapStyleOption.allCases, id: \.self) { style in
                    Button {
                        withAnimation {
                            selectedMapStyle = style
                        }
                    } label: {
                        HStack {
                            Text(style.rawValue)
                            if selectedMapStyle == style {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "map")
                    .font(.title3)
                    .foregroundStyle(AppTheme.purple)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark
                                  ? Color(.systemGray5)
                                  : .white)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    // MARK: - 底部資訊列
    private var bottomInfoBar: some View {
        HStack(spacing: 16) {
            // 對方頭像
            Circle()
                .fill(AppTheme.softGradient)
                .frame(width: 44, height: 44)
                .overlay(
                    Text("💕")
                        .font(.title3)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(partnerName)
                        .font(.headline)
                    
                    // 在線狀態
                    Circle()
                        .fill(webSocketManager.partnerOnline ? .green : .gray)
                        .frame(width: 8, height: 8)
                }
                
                // 電量顯示
                if partnerBattery >= 0 {
                    HStack(spacing: 4) {
                        batteryIcon
                        Text("\(partnerBattery)%")
                            .font(.subheadline)
                            .foregroundStyle(batteryColor)
                    }
                } else {
                    Text("電量未知")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // SOS 快捷按鈕
            NavigationLink {
                SOSView()
            } label: {
                Image(systemName: "sos.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.sosRed)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    // MARK: - 右側控制按鈕
    private var controlButtons: some View {
        VStack(spacing: 12) {
            // 定位到對方
            if let partnerLoc = partnerLocation {
                Button {
                    withAnimation {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: partnerLoc,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                    }
                } label: {
                    Image(systemName: "heart.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.pink)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        )
                }
            }
            
            // 定位到自己
            if let myLoc = myLocation {
                Button {
                    withAnimation {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: myLoc,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                    }
                } label: {
                    Image(systemName: "location.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        )
                }
            }
            
            // 顯示兩人
            Button {
                withAnimation {
                    cameraPosition = .automatic
                }
            } label: {
                Image(systemName: "person.2.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.purple)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    )
            }
        }
    }
    
    // MARK: - 電量圖示
    private var batteryIcon: some View {
        Group {
            if partnerBattery > 75 {
                Image(systemName: "battery.100")
            } else if partnerBattery > 50 {
                Image(systemName: "battery.75")
            } else if partnerBattery > 25 {
                Image(systemName: "battery.50")
            } else {
                Image(systemName: "battery.25")
            }
        }
        .foregroundStyle(batteryColor)
    }
    
    // 電量顏色
    private var batteryColor: Color {
        if partnerBattery > 50 { return .green }
        if partnerBattery > 20 { return .orange }
        return .red
    }
}

// MARK: - Preview
#Preview("地圖頁面") {
    NavigationStack {
        MapView()
            .environment(LocationManager())
            .environment(WebSocketManager())
            .environment(APIService())
    }
}

#Preview("深色模式") {
    NavigationStack {
        MapView()
            .environment(LocationManager())
            .environment(WebSocketManager())
            .environment(APIService())
    }
    .preferredColorScheme(.dark)
}
