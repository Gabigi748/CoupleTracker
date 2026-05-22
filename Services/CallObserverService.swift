// CallObserverService.swift
// CoupleTracker
//
// 通話監聽服務 — 使用 CXCallObserver 偵測本機通話狀態
// 當通話開始/結束時，透過 WebSocket 通知配對對象

import Foundation
import CallKit

/// 通話狀態
enum CallStatus: String, Sendable {
    case idle = "idle"
    case started = "started"
    case ended = "ended"
}

/// 通話監聯服務
/// 使用 CXCallObserver 偵測裝置通話狀態變化，並透過 WebSocket 通知對方
@MainActor
final class CallObserverService: NSObject, ObservableObject {
    
    // MARK: - 公開屬性
    
    /// 當前通話狀態
    @Published var currentStatus: CallStatus = .idle
    
    /// 是否正在通話中
    @Published var isOnCall: Bool = false
    
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
        callObserver.setDelegate(self, queue: DispatchQueue.main)
    }
}

// MARK: - CXCallObserverDelegate

extension CallObserverService: @preconcurrency CXCallObserverDelegate {
    
    /// 通話狀態變化回調
    nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let hasEnded = call.hasEnded
        let isOutgoing = call.isOutgoing
        let hasConnected = call.hasConnected
        
        Task { @MainActor [weak self] in
            self?.handleCallChange(hasEnded: hasEnded, isOutgoing: isOutgoing, hasConnected: hasConnected)
        }
    }
    
    /// 處理通話狀態變化
    private func handleCallChange(hasEnded: Bool, isOutgoing: Bool, hasConnected: Bool) {
        if hasEnded {
            // 通話結束
            if hasActiveCall {
                hasActiveCall = false
                isOnCall = false
                currentStatus = .ended
                sendCallStatus(.ended)
            }
        } else if isOutgoing && !hasConnected {
            // 撥出中（尚未接通）— 視為通話開始
            if !hasActiveCall {
                hasActiveCall = true
                isOnCall = true
                currentStatus = .started
                sendCallStatus(.started)
            }
        } else if !isOutgoing && !hasConnected && !hasEnded {
            // 來電響鈴中 — 視為通話開始
            if !hasActiveCall {
                hasActiveCall = true
                isOnCall = true
                currentStatus = .started
                sendCallStatus(.started)
            }
        } else if hasConnected && !hasEnded {
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
    private func sendCallStatus(_ status: CallStatus) {
        guard let webSocketManager else { return }
        webSocketManager.sendCallStatus(status: status.rawValue)
    }
}
