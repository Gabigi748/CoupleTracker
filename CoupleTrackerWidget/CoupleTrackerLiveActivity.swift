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
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                            .font(.caption)
                        Text(context.state.partnerName)
                            .font(.caption.bold())
                            .lineLimit(1)
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                            .font(.caption2)
                        Text(formatDistance(context.state.partnerDistance))
                            .font(.caption.bold())
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 12) {
                        // 電量
                        HStack(spacing: 3) {
                            Image(systemName: batteryIconName(context.state.partnerBattery))
                                .foregroundStyle(batteryColor(context.state.partnerBattery))
                                .font(.caption2)
                            Text("\(context.state.partnerBattery)%")
                                .font(.caption2)
                                .foregroundStyle(batteryColor(context.state.partnerBattery))
                        }
                        
                        // 移動狀態
                        HStack(spacing: 3) {
                            Image(systemName: activityIcon(context.state.partnerActivity))
                                .font(.caption2)
                            Text(activityText(context.state.partnerActivity))
                                .font(.caption2)
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Spacer()
                        Text("更新於 \(context.state.lastUpdateTime, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } compactLeading: {
                // 靈動島緊湊狀態 — 左邊：對方名字
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                        .font(.caption2)
                    Text(context.state.partnerName)
                        .font(.caption2.bold())
                        .lineLimit(1)
                }
            } compactTrailing: {
                // 靈動島緊湊狀態 — 右邊：距離
                Text(formatDistance(context.state.partnerDistance))
                    .font(.caption2.bold())
                    .foregroundStyle(.blue)
            } minimal: {
                // 最小狀態（與其他 Live Activity 共存時）
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .font(.caption)
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
    
    /// 格式化距離
    /// - < 1000m → "850m"
    /// - >= 1000m → "3.2km"
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        } else {
            return String(format: "%.1fkm", meters / 1000)
        }
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
    
    /// 移動狀態圖示
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
