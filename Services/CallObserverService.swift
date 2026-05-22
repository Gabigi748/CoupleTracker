// CallObserverService.swift
// CoupleTracker
//
// 通話監聽服務 — 使用 CXCallObserver 偵測本機通話狀態
// 當通話開始/結束時，透過 WebSocket 通知配對對象

import Foundation
import CallKit
import Observation

/// 通話狀態
enum CallStatus: String, Sendable {
    case idle = "idle"
    case started = "started"
    case ended = "ended"
}

/// 通話監聽服務
/// 使用 CXCallObserver 偵測裝置通話狀態變化，並透過 WebSocket 通知對方
@MainActor
@Observable
final class CallObserverService: NSObject {
    
    // MARK: - 公開屬性
    
    /// 當前通話狀態
    var currentStatus: CallStatus = .idle
    
    /// 是否正在通話中
    var isOnCall: Bool = false
    
    // MARK: - 私有屬性
    
    /// CXCallObserver 實例
    private let callObserver = CXCallObserver()
    
    /// WebSocket 管理器參考
    private weak var webSocketManager: WebSocketManager?
    
    /// 是否已有活躍通話（避免重複發送 started）
    private var hasActiveCall: Bool = false
    
    // MARK: - 初始化
    
    override init() {
        super.init()
    }
    
    // MARK: - 設定
    
    /// 設定並開始監聽通話狀態
    /// - Parameter webSocketManager: WebSocket 管理器（用於發送通話狀態）
    func configure(with webSocketManager: WebSocketManager) {
        self.webSocketManager = webSocketManager
        // CXCallObserverDelegate 的回調不在 MainActor，需要用 nonisolated wrapper
        callObserver.setDelegate(self, queue: DispatchQueue.main)
    }
}

// MARK: - CXCallObserverDelegate

extension CallObserverService: CXCallObserverDelegate {
    
    /// 通話狀態變化回調
    nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        Task { @MainActor in
            handleCallChange(call)
        }
    }
    
    /// 處理通話狀態變化
    @MainActor
    private func handleCallChange(_ call: CXCall) {
        if call.hasEnded {
            // 通話結束
            if hasActiveCall {
                hasActiveCall = false
                isOnCall = false
                currentStatus = .ended
                sendCallStatus(.ended)
            }
        } else if call.isOutgoing && !call.hasConnected {
            // 撥出中（尚未接通）— 視為通話開始
            if !hasActiveCall {
                hasActiveCall = true
                isOnCall = true
                currentStatus = .started
                sendCallStatus(.started)
            }
        } else if !call.isOutgoing && !call.hasConnected && !call.hasEnded {
            // 來電響鈴中 — 視為通話開始
            if !hasActiveCall {
                hasActiveCall = true
                isOnCall = true
                currentStatus = .started
                sendCallStatus(.started)
            }
        } else if call.hasConnected && !call.hasEnded {
            // 通話已接通
            if !hasActiveCall {
                hasActiveCall = true
                isOnCall = true
                currentStatus = .started
                sendCallStatus(.started)
            }
        }
    }
    
    /// 透過 WebSocket 發送通話狀態
    @MainActor
    private func sendCallStatus(_ status: CallStatus) {
        guard let webSocketManager else { return }
        webSocketManager.sendCallStatus(status: status.rawValue)
    }
}
