// MotionActivityManager.swift
// CoupleTracker
//
// Motion & Fitness 管理器
// 注意：不使用 @MainActor，因為 CoreMotion 回調在自己的 queue 上
// 使用 @unchecked Sendable 避免 Swift 6 isolation 問題

import Foundation
import CoreMotion
import Observation

/// 移動狀態列舉
enum MotionActivity: String, Codable, Sendable {
    case stationary = "stationary"
    case walking = "walking"
    case running = "running"
    case cycling = "cycling"
    case driving = "driving"
    case unknown = "unknown"
    
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
/// 不標記 @MainActor — CoreMotion 回調在自己的 dispatch queue 上
@Observable
final class MotionActivityManager: @unchecked Sendable {
    
    // MARK: - 公開屬性（只在主線程讀取，CoreMotion 回調透過 MainActor.run 更新）
    
    var currentActivity: MotionActivity = .unknown
    var todaySteps: Int = 0
    var isMonitoring: Bool = false
    var isAuthorized: Bool = false
    
    // MARK: - 私有屬性
    
    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    
    /// 活動變更回調
    @MainActor var onActivityChanged: ((MotionActivity) -> Void)?
    
    // MARK: - 初始化
    
    nonisolated init() {}
    
    // MARK: - 公開方法
    
    @MainActor
    func startMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("⚠️ 此裝置不支援 Motion Activity")
            return
        }
        
        guard !isMonitoring else { return }
        
        // 先用一次性查詢觸發權限請求
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        
        activityManager.queryActivityStarting(from: oneMinuteAgo, to: now, to: OperationQueue.main) { [weak self] _, error in
            guard let self else { return }
            
            if let error = error as? NSError {
                if error.domain == "CMErrorDomain", error.code == 105 {
                    print("⚠️ Motion Activity 未授權")
                    Task { @MainActor in
                        self.isAuthorized = false
                    }
                    return
                }
                print("⚠️ Motion Activity 查詢錯誤: \(error.localizedDescription)")
                return
            }
            
            Task { @MainActor in
                self.isAuthorized = true
                self.isMonitoring = true
            }
            self.startActivityUpdates()
            self.startPedometerUpdates()
        }
    }
    
    func stopMonitoring() {
        activityManager.stopActivityUpdates()
        pedometer.stopUpdates()
        Task { @MainActor in
            self.isMonitoring = false
        }
    }
    
    // MARK: - 私有方法
    
    private func startActivityUpdates() {
        // 使用自訂 queue，回調裡不直接存取 @Observable 屬性
        let queue = OperationQueue()
        queue.name = "com.fish.coupletracker.motion"
        queue.maxConcurrentOperationCount = 1
        
        activityManager.startActivityUpdates(to: queue) { [weak self] activity in
            guard let self else { return }
            guard let activity else { return }
            guard activity.confidence != .low else { return }
            
            let motionActivity = Self.mapActivity(activity)
            
            // 透過 MainActor.run 安全更新 UI 屬性
            Task { @MainActor in
                let previousActivity = self.currentActivity
                self.currentActivity = motionActivity
                self.isAuthorized = true
                
                if motionActivity != previousActivity {
                    self.onActivityChanged?(motionActivity)
                }
            }
        }
    }
    
    private func startPedometerUpdates() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        
        let startOfDay = Calendar.current.startOfDay(for: Date())
        
        // 查詢今日已有步數
        pedometer.queryPedometerData(from: startOfDay, to: Date()) { [weak self] data, _ in
            guard let self else { return }
            guard let steps = data?.numberOfSteps.intValue else { return }
            Task { @MainActor in
                self.todaySteps = steps
            }
        }
        
        // 即時更新
        pedometer.startUpdates(from: startOfDay) { [weak self] data, _ in
            guard let self else { return }
            guard let steps = data?.numberOfSteps.intValue else { return }
            Task { @MainActor in
                self.todaySteps = steps
            }
        }
    }
    
    private static func mapActivity(_ activity: CMMotionActivity) -> MotionActivity {
        if activity.automotive { return .driving }
        if activity.cycling { return .cycling }
        if activity.running { return .running }
        if activity.walking { return .walking }
        if activity.stationary { return .stationary }
        return .unknown
    }
}
