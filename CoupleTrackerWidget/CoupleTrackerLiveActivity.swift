// CoupleTrackerLiveActivity.swift
// CoupleTrackerWidget
//
// Live Activity UI — 靈動島（compact/expanded）+ 鎖屏即時資訊
// iOS 16.1+

import ActivityKit
import WidgetKit
import SwiftUI

struct CoupleTrackerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CoupleTrackerAttributes.self) { context in
            // 鎖屏 Live Activity UI（Lock Screen）
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // 靈動島展開狀態（Expanded）
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        // 可愛像素貓（根據移動狀態切換）
                        Image(catImageName(activity: context.state.partnerActivity, stationarySince: context.state.stationarySince))
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 28, height: 28)
                        Text(context.state.partnerName)
                            .font(.caption.bold())
                            .lineLimit(1)
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(distanceColor(context.state.partnerDistance))
                            .font(.caption2)
                        Text(formatDistance(context.state.partnerDistance))
                            .font(.caption.bold())
                            .foregroundStyle(distanceColor(context.state.partnerDistance))
                            .contentTransition(.numericText())
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 12) {
                        // 電量（SF Symbol + 顏色）
                        HStack(spacing: 3) {
                            Image(systemName: batteryIconName(context.state.partnerBattery))
                                .foregroundStyle(batteryColor(context.state.partnerBattery))
                                .font(.caption2)
                            Text("\(context.state.partnerBattery)%")
                                .font(.caption2.bold())
                                .foregroundStyle(batteryColor(context.state.partnerBattery))
                                .contentTransition(.numericText())
                        }
                        
                        // 移動狀態文字
                        HStack(spacing: 3) {
                            Image(systemName: activityIcon(context.state.partnerActivity))
                                .foregroundStyle(activityColor(context.state.partnerActivity))
                                .font(.caption2)
                            Text(activityText(context.state.partnerActivity))
                                .font(.caption2.bold())
                                .foregroundStyle(activityColor(context.state.partnerActivity))
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Spacer()
                        Text(distanceMood(context.state.partnerDistance))
                            .font(.caption2)
                        Text("・")
                            .foregroundStyle(.secondary)
                        Text(context.state.lastUpdateTime, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } compactLeading: {
                // 靈動島緊湊狀態 — 左邊：像素貓 + 對方名字
                HStack(spacing: 2) {
                    Image(catImageName(activity: context.state.partnerActivity, stationarySince: context.state.stationarySince))
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 20, height: 20)
                    Text(context.state.partnerName)
                        .font(.caption2.bold())
                        .lineLimit(1)
                }
            } compactTrailing: {
                // 靈動島緊湊狀態 — 右邊：距離（顏色隨距離變化）
                Text(formatDistance(context.state.partnerDistance))
                    .font(.caption2.bold())
                    .foregroundStyle(distanceColor(context.state.partnerDistance))
                    .contentTransition(.numericText())
            } minimal: {
                // 最小狀態 — 像素貓
                Image(catImageName(activity: context.state.partnerActivity, stationarySince: context.state.stationarySince))
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 22, height: 22)
            }
        }
    }
    
    // MARK: - 鎖屏 View
    
    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<CoupleTrackerAttributes>) -> some View {
        VStack(spacing: 12) {
            // 頂部：名字 + 距離
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                    Text(context.state.partnerName)
                        .font(.headline.bold())
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(formatDistance(context.state.partnerDistance))
                        .font(.title3.bold())
                        .foregroundStyle(.blue)
                }
            }
            
            // 中間：電量 + 移動狀態
            HStack(spacing: 20) {
                // 電量
                HStack(spacing: 6) {
                    Image(systemName: batteryIconName(context.state.partnerBattery))
                        .foregroundStyle(batteryColor(context.state.partnerBattery))
                    Text("\(context.state.partnerBattery)%")
                        .font(.subheadline)
                        .foregroundStyle(batteryColor(context.state.partnerBattery))
                }
                
                // 移動狀態
                HStack(spacing: 6) {
                    Image(systemName: activityIcon(context.state.partnerActivity))
                    Text(activityText(context.state.partnerActivity))
                        .font(.subheadline)
                }
                
                Spacer()
                
                // 最後更新時間
                Text(context.state.lastUpdateTime, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .activityBackgroundTint(.black.opacity(0.7))
        .activitySystemActionForegroundColor(.white)
    }
    
    // MARK: - Helper Functions
    
    /// 根據移動狀態選擇像素貓圖片
    /// - idle: 靜止（< 3小時）
    /// - walk: 走路
    /// - run: 快速移動（跑步/騎車/開車）
    /// - sleep: 長時間靜止（> 3小時）
    private func catImageName(activity: String, stationarySince: Date?) -> String {
        switch activity {
        case "walking":
            return "cat_walk"
        case "running", "cycling", "driving":
            return "cat_run"
        case "stationary":
            // 超過 3 小時沒移動 → 睡覺
            if let since = stationarySince {
                let hours = Date().timeIntervalSince(since) / 3600
                if hours >= 3 {
                    return "cat_sleep"
                }
            }
            return "cat_idle"
        default:
            return "cat_idle"
        }
    }
    
    /// 格式化距離
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
    }
    
    /// 距離顏色（越近越粉，越遠越藍）
    private func distanceColor(_ meters: Double) -> Color {
        if meters < 500 { return .pink }
        if meters < 2000 { return .purple }
        if meters < 10000 { return .blue }
        return .cyan
    }
    
    /// 距離心情文字
    private func distanceMood(_ meters: Double) -> String {
        if meters < 100 { return "就在身邊 ♡" }
        if meters < 500 { return "很近很近~" }
        if meters < 2000 { return "不遠不遠" }
        if meters < 10000 { return "有點想你" }
        if meters < 50000 { return "好想見你..." }
        return "想你想你想你"
    }
    
    /// 電量 emoji
    private func batteryEmoji(_ level: Int) -> String {
        if level > 75 { return "🔋" }
        if level > 50 { return "🔋" }
        if level > 20 { return "🪫" }
        return "🪫"
    }
    
    /// 電量圖示名稱
    private func batteryIconName(_ level: Int) -> String {
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        return "battery.25"
    }
    
    /// 電量顏色
    private func batteryColor(_ level: Int) -> Color {
        if level > 50 { return .green }
        if level > 20 { return .orange }
        return .red
    }
    
    /// 移動狀態 emoji
    private func activityEmoji(_ activity: String) -> String {
        switch activity {
        case "walking": return "🚶"
        case "running": return "🏃"
        case "cycling": return "🚴"
        case "driving": return "🚗"
        case "stationary": return "🧍"
        default: return "❓"
        }
    }
    
    /// 移動狀態顏色
    private func activityColor(_ activity: String) -> Color {
        switch activity {
        case "walking": return .green
        case "running": return .orange
        case "cycling": return .cyan
        case "driving": return .blue
        case "stationary": return .secondary
        default: return .secondary
        }
    }
    
    /// 移動狀態圖示（保留給鎖屏用）
    private func activityIcon(_ activity: String) -> String {
        switch activity {
        case "walking": return "figure.walk"
        case "running": return "figure.run"
        case "cycling": return "figure.outdoor.cycle"
        case "driving": return "car.fill"
        case "stationary": return "person.fill"
        default: return "questionmark.circle"
        }
    }
    
    /// 移動狀態文字
    private func activityText(_ activity: String) -> String {
        switch activity {
        case "walking": return "走路"
        case "running": return "跑步"
        case "cycling": return "騎車"
        case "driving": return "開車"
        case "stationary": return "靜止"
        default: return "未知"
        }
    }
}
