// MotionActivityManager.swift
// CoupleTracker
//
// Motion & Fitness 管理器 — 使用 CMMotionActivityManager 偵測移動狀態
// - 偵測：靜止、走路、跑步、騎車、開車
// - 計步：今日步數
// - 智慧定位：根據移動狀態調整 GPS 精度
//
// 注意：CMMotionActivityManager 的回調不在 MainActor 上，需要 Task { @MainActor in } 切換

import Foundation
import CoreMotion
import Observation

/// 移動狀態列舉
enum MotionActivity: String, Codable, Sendable {
    case stationary = "stationary"  // 靜止
    case walking = "walking"        // 走路
    case running = "running"        // 跑步
    case cycling = "cycling"        // 騎車
    case driving = "driving"        // 開車
    case unknown = "unknown"        // 未知
    
    /// 顯示用圖示（SF Symbol）
    var iconName: String {
        switch self {
        case .stationary: return "person.fill"
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .driving: return "car.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    
    /// 顯示用文字
    var displayText: String {
        switch self {
        case .stationary: return "靜止"
        case .walking: return "走路"
        case .running: return "跑步"
        case .cycling: return "騎車"
        case .driving: return "開車"
        case .unknown: return "未知"
        }
    }
}

/// Motion & Fitness 管理器
@MainActor
@Observable
final class MotionActivityManager {
    
    // MARK: - 公開屬性
    
    /// 當前移動狀態
    var currentActivity: MotionActivity = .unknown
    
    /// 步數（今日）
    var todaySteps: Int = 0
    
    /// 是否正在監控
    var isMonitoring: Bool = false
    
    /// 是否有 Motion 權限
    var isAuthorized: Bool = false
    
    // MARK: - 私有屬性
    
    /// Core Motion 活動管理器
    private let activityManager = CMMotionActivityManager()
    
    /// 計步器
    private let pedometer = CMPedometer()
    
    /// 活動變更回調（供外部使用，例如通知 WebSocket）
    var onActivityChanged: ((MotionActivity) -> Void)?
    
    // MARK: - 公開方法
    
    /// 開始監控移動狀態和步數
    func startMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("⚠️ 此裝置不支援 Motion Activity")
            return
        }
        
        guard !isMonitoring else { return }
        isMonitoring = true
        
        startActivityUpdates()
        startPedometerUpdates()
    }
    
    /// 停止監控
    func stopMonitoring() {
        activityManager.stopActivityUpdates()
        pedometer.stopUpdates()
        isMonitoring = false
    }
    
    // MARK: - 私有方法
    
    /// 開始接收活動更新
    private func startActivityUpdates() {
        // CMMotionActivityManager 的回調在 OperationQueue 上，不在 MainActor
        activityManager.startActivityUpdates(to: OperationQueue()) { [weak self] activity in
            guard let activity else { return }
            
            let motionActivity = Self.mapActivity(activity)
            
            // 切換到 MainActor 更新 UI 狀態
            Task { @MainActor [weak self] in
                guard let self else { return }
                let previousActivity = self.currentActivity
                self.currentActivity = motionActivity
                self.isAuthorized = true
                
                // 只在狀態真正改變時通知
                if motionActivity != previousActivity {
                    self.onActivityChanged?(motionActivity)
                }
            }
        }
    }
    
    /// 開始計步器更新（今日步數）
    private func startPedometerUpdates() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        
        // 取得今日開始時間
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        
        // 先查詢今日已有的步數
        pedometer.queryPedometerData(from: startOfDay, to: Date()) { [weak self] data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            Task { @MainActor [weak self] in
                self?.todaySteps = steps
            }
        }
        
        // 開始即時更新
        pedometer.startUpdates(from: startOfDay) { [weak self] data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            Task { @MainActor [weak self] in
                self?.todaySteps = steps
            }
        }
    }
    
    /// 將 CMMotionActivity 轉換為 MotionActivity
    private static func mapActivity(_ activity: CMMotionActivity) -> MotionActivity {
        // 優先級：driving > cycling > running > walking > stationary
        if activity.automotive { return .driving }
        if activity.cycling { return .cycling }
        if activity.running { return .running }
        if activity.walking { return .walking }
        if activity.stationary { return .stationary }
        return .unknown
    }
}
