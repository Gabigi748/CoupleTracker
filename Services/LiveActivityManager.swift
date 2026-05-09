// LiveActivityManager.swift
// CoupleTracker
//
// Live Activity 管理器 — 控制靈動島 + 鎖屏即時資訊的生命週期
// 安全設計：所有 ActivityKit 存取都延遲到確認可用後才執行
// 避免在背景啟動或未簽名環境下 crash

import Foundation
import ActivityKit
import UIKit
import Observation

/// Live Activity 管理器
@MainActor
@Observable
final class LiveActivityManager {
    
    // MARK: - 屬性
    
    /// 是否有活躍的 Live Activity
    var isActivityActive: Bool = false
    
    /// ActivityKit 是否可用（延遲檢查）
    private var activityKitAvailable: Bool?
    
    /// 當前 Live Activity 的 ID
    private var currentActivityId: String?
    
    /// Live Activity 啟動時間（用於 8 小時自動重啟）
    private var activityStartTime: Date?
    
    /// 8 小時自動重啟計時器
    private var restartTimer: Timer?
    
    /// Live Activity 最長持續時間（8 小時）
    private let maxDuration: TimeInterval = 8 * 60 * 60
    
    /// 對方開始靜止的時間（用於判斷是否顯示睡覺貓）
    private var stationarySince: Date?
    
    /// 上一次的移動狀態
    private var lastActivity: String?
    
    /// 最近一次的狀態快照（用於啟動/重啟新 Activity 時帶上當前資料）
    /// 避免新建 Activity 顯示 0m 直到下一次 updateLiveActivity 才刷新
    private var lastState: CoupleTrackerAttributes.ContentState?
    
    // MARK: - 安全檢查
    
    /// 安全檢查 ActivityKit 是否可用
    /// 在未簽名或背景啟動時可能不可用
    private func isActivityKitAvailable() -> Bool {
        // 快取結果
        if let cached = activityKitAvailable {
            return cached
        }
        
        guard #available(iOS 16.2, *) else {
            activityKitAvailable = false
            return false
        }
        
        // iOS 16.2+ 允許在背景啟動 Live Activity（只要有 Info.plist 的
        // NSSupportsLiveActivities）所以這裡不再阻擋背景狀態。如果後續
        // Activity.request 失敗，會在 doStartLiveActivity 捕捉錯誤。
        activityKitAvailable = true
        return true
    }
    
    // MARK: - 公開方法
    
    /// 開始 Live Activity
    func startLiveActivity(myName: String, partnerName: String) {
        guard isActivityKitAvailable() else {
            print("[LiveActivity] ActivityKit 不可用，跳過")
            return
        }
        
        // 延遲啟動，避免在 App 初始化階段就存取 ActivityKit
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            
            self.doStartLiveActivity(myName: myName, partnerName: partnerName)
        }
    }
    
    /// 確保 Live Activity 存在（前景化時呼叫）
    /// 若系統的 activities list 為空（被系統收掉或使用者滑掉），則重新啟動
    func ensureLiveActivity(myName: String, partnerName: String) {
        guard isActivityKitAvailable() else { return }
        
        Task { @MainActor in
            // 檢查系統層面是否還有活躍的 activity
            let activeCount = Activity<CoupleTrackerAttributes>.activities.count
            
            if activeCount == 0 {
                print("[LiveActivity] 系統層面無活躍 Activity，重新啟動")
                self.isActivityActive = false
                self.currentActivityId = nil
                self.doStartLiveActivity(myName: myName, partnerName: partnerName)
            } else if !self.isActivityActive {
                // 狀態不一致，同步一下
                print("[LiveActivity] 狀態不一致，同步本地狀態")
                self.isActivityActive = true
                if let first = Activity<CoupleTrackerAttributes>.activities.first {
                    self.currentActivityId = first.id
                    self.observeActivityState(first, myName: myName, partnerName: partnerName)
                }
            }
        }
    }
    
    /// 更新 Live Activity
    func updateLiveActivity(
        partnerName: String,
        distance: Double,
        battery: Int,
        activity: String,
        charging: Bool = false
    ) {
        // 以系統實際狀態為準（比 local flag 可靠）
        let systemActivities = Activity<CoupleTrackerAttributes>.activities
        guard !systemActivities.isEmpty else {
            // 系統沒有活躍的 Activity，同步 local flag
            if isActivityActive {
                isActivityActive = false
                currentActivityId = nil
            }
            return
        }
        
        // 同步 local flag（如果之前不一致）
        if !isActivityActive {
            isActivityActive = true
            if currentActivityId == nil {
                currentActivityId = systemActivities.first?.id
            }
        }
        
        // 追蹤靜止開始時間
        if activity == "stationary" {
            if lastActivity != "stationary" {
                // 剛變成靜止，記錄開始時間
                stationarySince = Date()
            }
        } else {
            // 不是靜止，清除
            stationarySince = nil
        }
        lastActivity = activity
        
        let updatedState = CoupleTrackerAttributes.ContentState(
            partnerName: partnerName,
            partnerDistance: distance,
            partnerBattery: battery,
            partnerActivity: activity,
            partnerCharging: charging,
            lastUpdateTime: Date(),
            stationarySince: stationarySince
        )
        
        // 記錄最新狀態，下次重啟新 Activity 會用到
        lastState = updatedState
        
        let content = ActivityContent(state: updatedState, staleDate: nil)
        
        Task.detached {
            for activity in systemActivities {
                await activity.update(content)
            }
        }
    }
    
    /// 結束 Live Activity
    func endLiveActivity() {
        restartTimer?.invalidate()
        restartTimer = nil
        
        cleanupAllActivities()
        activityStartTime = nil
        
        print("[LiveActivity] 已結束")
    }
    
    // MARK: - 私有方法
    
    /// 實際啟動 Live Activity
    private func doStartLiveActivity(myName: String, partnerName: String) {
        // 安全檢查 areActivitiesEnabled
        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            print("[LiveActivity] Live Activities 未啟用")
            return
        }
        
        // 如果系統已有活躍 Activity，不再重複建立（避免疊加）
        if !Activity<CoupleTrackerAttributes>.activities.isEmpty {
            print("[LiveActivity] 系統已有活躍 Activity，跳過建立")
            if let first = Activity<CoupleTrackerAttributes>.activities.first {
                self.currentActivityId = first.id
                self.isActivityActive = true
                self.observeActivityState(first, myName: myName, partnerName: partnerName)
            }
            return
        }
        
        // 直接建立新的（不先清理舊的，避免空白過場）
        Task { @MainActor in
            let attributes = CoupleTrackerAttributes(myName: myName)
            // 使用上一次的狀態（若有），避免新 Activity 顯示 0m
            let initialState = self.lastState ?? CoupleTrackerAttributes.ContentState(
                partnerName: partnerName,
                partnerDistance: 0,
                partnerBattery: -1,
                partnerActivity: "unknown",
                partnerCharging: false,
                lastUpdateTime: Date(),
                stationarySince: nil
            )
            
            let content = ActivityContent(state: initialState, staleDate: nil)
            
            do {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                self.currentActivityId = activity.id
                self.isActivityActive = true
                self.activityStartTime = Date()
                
                // 設定 8 小時自動重啟
                self.scheduleRestart(myName: myName, partnerName: partnerName)
                
                // 監聽 Activity 狀態變化（被滑掉時自動重啟）
                self.observeActivityState(activity, myName: myName, partnerName: partnerName)
                
                print("[LiveActivity] 已啟動：\(activity.id)")
            } catch {
                print("[LiveActivity] 啟動失敗：\(error.localizedDescription)")
                self.activityKitAvailable = false
            }
        }
    }
    
    /// 清理所有舊的 Live Activity
    private func cleanupAllActivities() {
        Task.detached {
            for activity in Activity<CoupleTrackerAttributes>.activities {
                let finalState = CoupleTrackerAttributes.ContentState(
                    partnerName: "",
                    partnerDistance: 0,
                    partnerBattery: 0,
                    partnerActivity: "unknown",
                    partnerCharging: false,
                    lastUpdateTime: Date(),
                    stationarySince: nil
                )
                let content = ActivityContent(state: finalState, staleDate: nil)
                await activity.end(content, dismissalPolicy: .immediate)
            }
        }
        currentActivityId = nil
        isActivityActive = false
    }
    
    /// 監聽 Activity 狀態變化，被使用者滑掉時自動重啟
    private func observeActivityState(
        _ activity: Activity<CoupleTrackerAttributes>,
        myName: String,
        partnerName: String
    ) {
        Task { @MainActor in
            for await state in activity.activityStateUpdates {
                switch state {
                case .dismissed:
                    print("[LiveActivity] 被使用者滑掉或被系統收掉，立即重啟")
                    self.isActivityActive = false
                    self.currentActivityId = nil
                    // 立即重啟（不延遲）— 減少位置 icon 過場時間
                    if UIApplication.shared.applicationState != .background {
                        self.doStartLiveActivity(myName: myName, partnerName: partnerName)
                    }
                    return
                case .ended:
                    print("[LiveActivity] 已結束")
                    self.isActivityActive = false
                    self.currentActivityId = nil
                    return
                case .active, .stale:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    /// 排程 8 小時後自動重啟 Live Activity
    private func scheduleRestart(myName: String, partnerName: String) {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(
            withTimeInterval: maxDuration - 60,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                print("🔄 Live Activity 即將到期，自動重啟")
                self.endLiveActivity()
                try? await Task.sleep(for: .seconds(2))
                self.startLiveActivity(myName: myName, partnerName: partnerName)
            }
        }
    }
}
