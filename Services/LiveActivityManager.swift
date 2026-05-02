// LiveActivityManager.swift
// CoupleTracker
//
// Live Activity 管理器 — 控制靈動島 + 鎖屏即時資訊的生命週期
// - startLiveActivity()：App 啟動時開始
// - updateLiveActivity()：收到對方位置更新時更新
// - endLiveActivity()：App 結束或登出時停止
//
// 注意：ActivityKit API 不在 MainActor 上，需要 nonisolated 或 Task 切換

import Foundation
import ActivityKit
import Observation

/// Live Activity 管理器
@MainActor
@Observable
final class LiveActivityManager {
    
    // MARK: - 屬性
    
    /// 是否有活躍的 Live Activity
    var isActivityActive: Bool = false
    
    /// 當前 Live Activity 的 ID
    private var currentActivityId: String?
    
    /// Live Activity 啟動時間（用於 8 小時自動重啟）
    private var activityStartTime: Date?
    
    /// 8 小時自動重啟計時器
    private var restartTimer: Timer?
    
    /// Live Activity 最長持續時間（8 小時）
    private let maxDuration: TimeInterval = 8 * 60 * 60
    
    // MARK: - 公開方法
    
    /// 開始 Live Activity
    /// - Parameters:
    ///   - myName: 自己的名字
    ///   - partnerName: 對方的名字
    func startLiveActivity(myName: String, partnerName: String) {
        // 檢查是否支援 Live Activities
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ Live Activities 未啟用")
            return
        }
        
        // 如果已有活躍的 Activity，先結束
        if isActivityActive {
            endLiveActivity()
        }
        
        let attributes = CoupleTrackerAttributes(myName: myName)
        let initialState = CoupleTrackerAttributes.ContentState(
            partnerName: partnerName,
            partnerDistance: 0,
            partnerBattery: -1,
            partnerActivity: "unknown",
            lastUpdateTime: Date()
        )
        
        let content = ActivityContent(state: initialState, staleDate: nil)
        
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivityId = activity.id
            isActivityActive = true
            activityStartTime = Date()
            
            // 設定 8 小時自動重啟
            scheduleRestart(myName: myName, partnerName: partnerName)
            
            print("✅ Live Activity 已啟動：\(activity.id)")
        } catch {
            print("❌ Live Activity 啟動失敗：\(error.localizedDescription)")
        }
    }
    
    /// 更新 Live Activity
    /// - Parameters:
    ///   - partnerName: 對方名字
    ///   - distance: 距離（公尺）
    ///   - battery: 電量（0-100）
    ///   - activity: 移動狀態
    func updateLiveActivity(
        partnerName: String,
        distance: Double,
        battery: Int,
        activity: String
    ) {
        guard isActivityActive else { return }
        
        let updatedState = CoupleTrackerAttributes.ContentState(
            partnerName: partnerName,
            partnerDistance: distance,
            partnerBattery: battery,
            partnerActivity: activity,
            lastUpdateTime: Date()
        )
        
        let content = ActivityContent(state: updatedState, staleDate: nil)
        
        // ActivityKit 的 update 不在 MainActor 上
        Task.detached {
            for activity in Activity<CoupleTrackerAttributes>.activities {
                await activity.update(content)
            }
        }
    }
    
    /// 結束 Live Activity
    func endLiveActivity() {
        restartTimer?.invalidate()
        restartTimer = nil
        
        let finalState = CoupleTrackerAttributes.ContentState(
            partnerName: "",
            partnerDistance: 0,
            partnerBattery: 0,
            partnerActivity: "unknown",
            lastUpdateTime: Date()
        )
        
        let content = ActivityContent(state: finalState, staleDate: nil)
        
        Task.detached {
            for activity in Activity<CoupleTrackerAttributes>.activities {
                await activity.end(content, dismissalPolicy: .immediate)
            }
        }
        
        currentActivityId = nil
        isActivityActive = false
        activityStartTime = nil
        
        print("🛑 Live Activity 已結束")
    }
    
    // MARK: - 私有方法
    
    /// 排程 8 小時後自動重啟 Live Activity
    private func scheduleRestart(myName: String, partnerName: String) {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(
            withTimeInterval: maxDuration - 60, // 提前 1 分鐘重啟
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                print("🔄 Live Activity 即將到期，自動重啟")
                self.endLiveActivity()
                // 短暫延遲後重啟
                try? await Task.sleep(for: .seconds(2))
                self.startLiveActivity(myName: myName, partnerName: partnerName)
            }
        }
    }
}
