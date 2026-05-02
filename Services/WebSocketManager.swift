// WebSocketManager.swift
// CoupleTracker
//
// WebSocket 管理器 — 即時通訊（位置更新、聊天訊息、SOS 警報）
// 使用 URLSessionWebSocketTask + 自動重連 + 心跳機制

import Foundation
import Observation

/// WebSocket 連線狀態
enum WebSocketConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

/// WebSocket 管理器
/// 負責即時通訊：位置更新、聊天訊息、SOS 警報
@MainActor
@Observable
final class WebSocketManager {
    
    // MARK: - 公開屬性
    
    /// 對方即時位置
    var partnerLocation: Location?
    
    /// 最新收到的聊天訊息
    var newMessage: ChatMessage?
    
    /// 所有即時聊天訊息
    var messages: [ChatMessage] = []
    
    /// SOS 警報觸發
    var sosAlert: Bool = false
    
    /// SOS 警報位置
    var sosLocation: Location?
    
    /// 連線狀態
    var connectionState: WebSocketConnectionState = .disconnected
    
    /// 對方電量
    var partnerBattery: Int?
    
    // MARK: - 私有屬性
    
    /// WebSocket 連線
    private var webSocket: URLSessionWebSocketTask?
    
    /// WebSocket URL
    private let wsURL = "wss://anzufish.org/couple-ws"
    
    /// JWT Token
    private var token: String?
    
    /// 心跳計時器
    private var heartbeatTimer: Timer?
    
    /// 重連計時器
    private var reconnectTimer: Timer?
    
    /// 重連嘗試次數（用於 exponential backoff）
    private var reconnectAttempts: Int = 0
    
    /// 最大重連嘗試次數
    private let maxReconnectAttempts: Int = 10
    
    /// 是否主動斷線（避免自動重連）
    private var isManualDisconnect: Bool = false
    
    /// URLSession 實例
    private let session: URLSession
    
    // MARK: - 初始化
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - 連線管理
    
    /// 建立 WebSocket 連線
    /// - Parameter token: JWT Token（用於身份驗證）
    func connect(token: String) {
        self.token = token
        isManualDisconnect = false
        reconnectAttempts = 0
        
        establishConnection()
    }
    
    /// 主動斷開 WebSocket 連線
    func disconnect() {
        isManualDisconnect = true
        cleanup()
        connectionState = .disconnected
    }
    
    /// 發送位置更新
    /// - Parameter location: 當前位置
    func sendLocation(_ location: Location) {
        let payload: [String: Any] = [
            "type": "location_update",
            "data": [
                "latitude": location.latitude,
                "longitude": location.longitude,
                "accuracy": 10.0,
                "battery": UIDevice.current.batteryLevel >= 0
                    ? Int(UIDevice.current.batteryLevel * 100)
                    : -1,
                "timestamp": ISO8601DateFormatter().string(from: location.timestamp)
            ]
        ]
        
        sendJSON(payload)
    }
    
    /// 發送聊天訊息
    /// - Parameter text: 訊息文字
    func sendChat(_ text: String) {
        let payload: [String: Any] = [
            "type": "chat_message",
            "data": [
                "text": text,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        ]
        
        sendJSON(payload)
    }
    
    /// 發送 SOS 緊急訊息
    /// - Parameters:
    ///   - latitude: 緯度
    ///   - longitude: 經度
    func sendSOS(latitude: Double, longitude: Double) {
        let payload: [String: Any] = [
            "type": "sos",
            "data": [
                "latitude": latitude,
                "longitude": longitude,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        ]
        
        sendJSON(payload)
    }
    
    // MARK: - 私有方法
    
    /// 建立 WebSocket 連線
    private func establishConnection() {
        // 組合帶 Token 的 URL
        guard let url = URL(string: "\(wsURL)?token=\(token ?? "")") else {
            connectionState = .disconnected
            return
        }
        
        connectionState = reconnectAttempts > 0 ? .reconnecting : .connecting
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
        
        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()
        
        // 開始接收訊息
        receiveMessage()
        
        // 啟動心跳
        startHeartbeat()
        
        connectionState = .connected
        reconnectAttempts = 0
    }
    
    /// 接收 WebSocket 訊息（遞迴呼叫）
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    // 繼續接收下一則訊息
                    self.receiveMessage()
                    
                case .failure(let error):
                    print("❌ WebSocket 接收錯誤：\(error.localizedDescription)")
                    self.handleDisconnection()
                }
            }
        }
    }
    
    /// 處理收到的訊息
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseJSON(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseJSON(text)
            }
        @unknown default:
            break
        }
    }
    
    /// 解析 JSON 訊息
    private func parseJSON(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let payload = json["data"] as? [String: Any] else {
            return
        }
        
        switch type {
        case "location_update":
            handleLocationUpdate(payload)
            
        case "chat_message":
            handleChatMessage(payload)
            
        case "sos":
            handleSOSAlert(payload)
            
        case "partner_battery":
            if let battery = payload["battery_level"] as? Int {
                partnerBattery = battery
            }
            
        case "pong":
            // 心跳回應，連線正常
            break
            
        default:
            print("⚠️ 未知的 WebSocket 訊息類型：\(type)")
        }
    }
    
    /// 處理對方位置更新
    private func handleLocationUpdate(_ data: [String: Any]) {
        guard let latitude = data["latitude"] as? Double,
              let longitude = data["longitude"] as? Double else {
            return
        }
        
        let timestamp: Date
        if let timestampStr = data["timestamp"] as? String {
            timestamp = ISO8601DateFormatter().date(from: timestampStr) ?? Date()
        } else {
            timestamp = Date()
        }
        
        partnerLocation = Location(
            latitude: latitude,
            longitude: longitude,
            timestamp: timestamp
        )
        
        // 更新對方電量
        if let battery = data["battery"] as? Int, battery >= 0 {
            partnerBattery = battery
        }
    }
    
    /// 處理聊天訊息
    private func handleChatMessage(_ data: [String: Any]) {
        guard let id = data["id"] as? String,
              let senderId = data["sender_id"] as? String,
              let text = data["text"] as? String else {
            return
        }
        
        let timestamp: Date
        if let timestampStr = data["timestamp"] as? String {
            timestamp = ISO8601DateFormatter().date(from: timestampStr) ?? Date()
        } else {
            timestamp = Date()
        }
        
        let message = ChatMessage(
            id: id,
            senderId: senderId,
            text: text,
            timestamp: timestamp,
            isRead: false,
            messageType: .text
        )
        
        newMessage = message
        messages.append(message)
    }
    
    /// 處理 SOS 警報
    private func handleSOSAlert(_ data: [String: Any]) {
        sosAlert = true
        
        if let latitude = data["latitude"] as? Double,
           let longitude = data["longitude"] as? Double {
            sosLocation = Location(
                latitude: latitude,
                longitude: longitude,
                timestamp: Date()
            )
        }
    }
    
    /// 發送 JSON 訊息
    private func sendJSON(_ payload: [String: Any]) {
        guard connectionState == .connected else { return }
        
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        
        webSocket?.send(.string(text)) { error in
            if let error {
                print("❌ WebSocket 發送錯誤：\(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 心跳機制
    
    /// 啟動心跳（每 30 秒 ping 一次）
    private func startHeartbeat() {
        stopHeartbeat()
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendPing()
            }
        }
    }
    
    /// 停止心跳
    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }
    
    /// 發送 ping
    private func sendPing() {
        let payload: [String: Any] = ["type": "ping"]
        sendJSON(payload)
        
        // 同時使用 URLSessionWebSocketTask 的 ping
        webSocket?.sendPing { [weak self] error in
            if let error {
                print("❌ Ping 失敗：\(error.localizedDescription)")
                Task { @MainActor [weak self] in
                    self?.handleDisconnection()
                }
            }
        }
    }
    
    // MARK: - 重連機制
    
    /// 處理斷線
    private func handleDisconnection() {
        guard !isManualDisconnect else { return }
        
        cleanup()
        connectionState = .reconnecting
        
        scheduleReconnect()
    }
    
    /// 排程重連（Exponential Backoff）
    private func scheduleReconnect() {
        guard reconnectAttempts < maxReconnectAttempts else {
            connectionState = .disconnected
            print("❌ 已達最大重連次數，停止重連")
            return
        }
        
        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s...（最大 60 秒）
        let delay = min(pow(2.0, Double(reconnectAttempts)), 60.0)
        reconnectAttempts += 1
        
        print("🔄 將在 \(delay) 秒後重連（第 \(reconnectAttempts) 次嘗試）")
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.establishConnection()
            }
        }
    }
    
    /// 清理資源
    private func cleanup() {
        stopHeartbeat()
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
    }
}
