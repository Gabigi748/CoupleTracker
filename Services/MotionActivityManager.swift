// MotionActivityManager.swift
// CoupleTracker
//
// Motion & Fitness 管理器 — 使用 CMMotionActivityManager 偵測移動狀態
// 注意：所有 CMMotionActivityManager 回調都不在 MainActor 上
// 使用 DispatchQueue.main.async 而非 Task { @MainActor in } 避免 Swift 6 isolation crash

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
@MainActor
@Observable
final class MotionActivityManager {
    
    // MARK: - 公開屬性
    
    var currentActivity: MotionActivity = .unknown
    var todaySteps: Int = 0
    var isMonitoring: Bool = false
    var isAuthorized: Bool = false
    
    // MARK: - 私有屬性
    
    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    
    /// 活動變更回調
    var onActivityChanged: ((MotionActivity) -> Void)?
    
    // MARK: - 公開方法
    
    func startMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("⚠️ 此裝置不支援 Motion Activity")
            return
        }
        
        guard !isMonitoring else { return }
        
        // 先用一次性查詢觸發權限請求
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        
        // 使用 OperationQueue.main 確保回調在主線程
        activityManager.queryActivityStarting(from: oneMinuteAgo, to: now, to: OperationQueue.main) { [weak self] _, error in
            // 已經在主線程上（OperationQueue.main）
            guard let self else { return }
            
            if let error = error as? NSError {
                if error.domain == "CMErrorDomain", error.code == 105 {
                    print("⚠️ Motion Activity 未授權")
                    self.isAuthorized = false
                    return
                }
                print("⚠️ Motion Activity 查詢錯誤: \(error.localizedDescription)")
                return
            }
            
            self.isAuthorized = true
            self.isMonitoring = true
            self.startActivityUpdates()
            self.startPedometerUpdates()
        }
    }
    
    func stopMonitoring() {
        activityManager.stopActivityUpdates()
        pedometer.stopUpdates()
        isMonitoring = false
    }
    
    // MARK: - 私有方法
    
    private func startActivityUpdates() {
        // 關鍵：使用 OperationQueue.main 讓回調直接在主線程執行
        // 這樣就不會觸發 Swift 6 的 MainActor isolation 檢查
        activityManager.startActivityUpdates(to: OperationQueue.main) { [weak self] activity in
            guard let self else { return }
            guard let activity else { return }
            guard activity.confidence != .low else { return }
            
            let motionActivity = Self.mapActivity(activity)
            let previousActivity = self.currentActivity
            self.currentActivity = motionActivity
            self.isAuthorized = true
            
            if motionActivity != previousActivity {
                self.onActivityChanged?(motionActivity)
            }
        }
    }
    
    private func startPedometerUpdates() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        
        let startOfDay = Calendar.current.startOfDay(for: Date())
        
        // 查詢今日已有步數
        pedometer.queryPedometerData(from: startOfDay, to: Date()) { [weak self] data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            DispatchQueue.main.async {
                self?.todaySteps = steps
            }
        }
        
        // 即時更新
        pedometer.startUpdates(from: startOfDay) { [weak self] data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            DispatchQueue.main.async {
                self?.todaySteps = steps
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
