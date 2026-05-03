// WebSocketManager.swift
// CoupleTracker
//
// WebSocket 管理器 — 即時通訊（位置更新、聊天訊息、SOS 警報、螢幕狀態）
// 使用 URLSessionWebSocketTask + 自動重連 + 心跳機制

import Foundation
import UIKit
import Observation

/// WebSocket 連線狀態
enum WebSocketConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

/// WebSocket 管理器
/// 負責即時通訊：位置更新、聊天訊息、SOS 警報、螢幕狀態
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
    
    /// 對方是否在線
    var partnerOnline: Bool = false
    
    /// 對方螢幕狀態事件（供 NotificationService 使用）
    var partnerScreenEvent: ScreenEvent?
    
    /// 對方圍欄事件（供 NotificationService 使用）
    var partnerGeofenceEvent: PartnerGeofenceEvent?
    
    /// 對方移動狀態
    var partnerActivity: String = "unknown"
    
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
    
    /// 最大重連嘗試次數（背景保活需要持續重連）
    private let maxReconnectAttempts: Int = 50
    
    /// 是否主動斷線（避免自動重連）
    private var isManualDisconnect: Bool = false
    
    /// URLSession 實例
    private let session: URLSession
    
    /// 螢幕狀態節流：上次發送螢幕開啟的時間
    private var lastScreenOnSent: Date?
    
    /// 螢幕狀態節流：上次發送螢幕關閉的時間
    private var lastScreenOffSent: Date?
    
    /// 螢幕狀態節流間隔（60 秒）
    private let screenThrottleInterval: TimeInterval = 60
    
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
        startScreenMonitoring()
    }
    
    /// 主動斷開 WebSocket 連線
    func disconnect() {
        isManualDisconnect = true
        stopScreenMonitoring()
        cleanup()
        connectionState = .disconnected
    }
    
    /// 發送位置更新
    /// - Parameter location: 當前位置
    func sendLocation(_ location: Location) {
        // 後端期望格式：{"type":"location","lat":...,"lng":...,"accuracy":...,"battery":...,"timestamp":...,"in_china":...}
        let battery = UIDevice.current.batteryLevel >= 0
            ? Int(UIDevice.current.batteryLevel * 100)
            : -1
        
        // 附帶 in_china 標記，讓接收端判斷是否需要座標轉換
        let inChina = CoordinateConverter.isInsideChina(lat: location.latitude, lng: location.longitude)
        
        let payload: [String: Any] = [
            "type": "location",
            "lat": location.latitude,
            "lng": location.longitude,
            "accuracy": location.accuracy ?? 10.0,
            "battery": battery,
            "timestamp": ISO8601DateFormatter().string(from: location.timestamp),
            "in_china": inChina
        ]
        
        sendJSON(payload)
    }
    
    /// 發送聊天訊息
    /// - Parameter text: 訊息文字
    func sendChat(_ text: String) {
        // 後端期望格式：{"type":"chat","text":...}
        let payload: [String: Any] = [
            "type": "chat",
            "text": text
        ]
        
        sendJSON(payload)
    }
    
    /// 發送 SOS 緊急訊息
    /// - Parameters:
    ///   - latitude: 緯度
    ///   - longitude: 經度
    func sendSOS(latitude: Double, longitude: Double) {
        // 後端 SOS 路由期望 REST API，但也可以透過 WebSocket 發送
        // 後端 websocket handler 有 sos type
        let payload: [String: Any] = [
            "type": "sos",
            "lat": latitude,
            "lng": longitude,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        sendJSON(payload)
    }
    
    /// 發送螢幕狀態
    /// - Parameter isOn: 螢幕是否開啟
    func sendScreenStatus(isOn: Bool) {
        // 節流：一分鐘內同類型事件不重複發送
        let now = Date()
        
        if isOn {
            if let last = lastScreenOnSent, now.timeIntervalSince(last) < screenThrottleInterval {
                return
            }
            lastScreenOnSent = now
        } else {
            if let last = lastScreenOffSent, now.timeIntervalSince(last) < screenThrottleInterval {
                return
            }
            lastScreenOffSent = now
        }
        
        let payload: [String: Any] = [
            "type": "screen_status",
            "status": isOn ? "on" : "off",
            "screen_on": isOn,
            "timestamp": ISO8601DateFormatter().string(from: now)
        ]
        
        sendJSON(payload)
    }
    
    /// 發送地理圍欄事件
    /// - Parameters:
    ///   - zoneName: 圍欄名稱
    ///   - event: 事件類型（"entry" 或 "exit"）
    func sendGeofenceEvent(zoneName: String, event: String) {
        let payload: [String: Any] = [
            "type": "geofence_event",
            "zone_name": zoneName,
            "event": event
        ]
        
        sendJSON(payload)
    }
    
    /// 發送移動狀態給對方
    /// - Parameter activity: 移動狀態字串（"walking", "driving", "stationary" 等）
    func sendMotionActivity(_ activity: String) {
        let payload: [String: Any] = [
            "type": "motion_activity",
            "activity": activity
        ]
        
        sendJSON(payload)
    }
    
    // MARK: - 螢幕監聽
    
    /// 開始監聽螢幕開關
    private func startScreenMonitoring() {
        // 啟用電池監控
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        // 螢幕解鎖（真正的螢幕開啟）
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendScreenStatus(isOn: true)
            }
        }
        
        // 螢幕鎖定（真正的螢幕關閉）
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendScreenStatus(isOn: false)
            }
        }
    }
    
    /// 停止監聽螢幕開關
    private func stopScreenMonitoring() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil
        )
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
    /// 後端發送的格式是頂層 JSON（不包在 data 裡）
    private func parseJSON(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        
        switch type {
        case "connected":
            // 連線成功確認
            print("✅ WebSocket 連線成功")
            
        case "location":
            // 後端轉發格式：{"type":"location","user_id":...,"lat":...,"lng":...,"accuracy":...,"battery":...,"timestamp":...}
            handleLocationUpdate(json)
            
        case "chat":
            // 後端轉發格式：{"type":"chat","id":...,"sender_id":...,"text":...,"timestamp":...}
            handleChatMessage(json)
            
        case "chat_ack":
            // 聊天訊息確認（自己發送的回執）
            // 可以用來更新訊息狀態，目前忽略
            break
            
        case "sos":
            // 後端轉發格式：{"type":"sos","sender_id":...,"sender_name":...,"lat":...,"lng":...,"timestamp":...}
            handleSOSAlert(json)
            
        case "partner_status":
            // 對方上線/離線：{"type":"partner_status","user_id":...,"online":...,"timestamp":...}
            if let online = json["online"] as? Bool {
                partnerOnline = online
            }
            
        case "screen_status":
            // 對方螢幕狀態：{"type":"screen_status","user_id":...,"screen_on":...,"timestamp":...}
            handleScreenStatus(json)
            
        case "geofence_event":
            // 對方圍欄事件：{"type":"geofence_event","user_id":...,"zone_name":...,"event":...,"text":...}
            handleGeofenceEventReceived(json)
            
        case "motion_activity":
            // 對方移動狀態：{"type":"motion_activity","user_id":...,"activity":...}
            if let activity = json["activity"] as? String {
                partnerActivity = activity
            }
            
        case "pong":
            // 心跳回應，連線正常
            break
            
        case "error":
            if let error = json["error"] as? String {
                print("⚠️ WebSocket 錯誤：\(error)")
            }
            
        default:
            print("⚠️ 未知的 WebSocket 訊息類型：\(type)")
        }
    }
    
    /// 處理對方位置更新
    /// 後端格式：{"type":"location","user_id":...,"lat":...,"lng":...,"accuracy":...,"battery":...,"timestamp":...,"in_china":...}
    ///
    /// GCJ-02 座標偏移修正邏輯：
    /// - 只有「自己在中國（MapKit 用高德/GCJ-02）+ 對方不在中國（座標是 WGS-84）」時
    ///   需要把對方的 WGS-84 座標轉成 GCJ-02，才能在高德地圖上正確顯示
    /// - 其他情況不需要轉換
    private func handleLocationUpdate(_ json: [String: Any]) {
        guard let lat = json["lat"] as? Double,
              let lng = json["lng"] as? Double else {
            return
        }
        
        let timestamp: Date
        if let timestampStr = json["timestamp"] as? String {
            timestamp = ISO8601DateFormatter().date(from: timestampStr) ?? Date()
        } else if let timestampMs = json["timestamp"] as? Double {
            timestamp = Date(timeIntervalSince1970: timestampMs / 1000)
        } else {
            timestamp = Date()
        }
        
        // GCJ-02 座標偏移修正
        var displayLat = lat
        var displayLng = lng
        
        let partnerInChina = json["in_china"] as? Bool ?? false
        let selfInChina = CoordinateConverter.isDeviceInChina
        
        if selfInChina && !partnerInChina {
            // 自己在中國（MapKit 用高德 GCJ-02），對方不在中國（WGS-84）
            // 需要把對方的 WGS-84 座標轉成 GCJ-02
            let converted = CoordinateConverter.wgs84ToGcj02(lat: lat, lng: lng)
            displayLat = converted.lat
            displayLng = converted.lng
        }
        
        partnerLocation = Location(
            latitude: displayLat,
            longitude: displayLng,
            timestamp: timestamp
        )
        
        // 更新對方電量
        if let battery = json["battery"] as? Int, battery >= 0 {
            partnerBattery = battery
        }
    }
    
    /// 處理聊天訊息
    /// 後端格式：{"type":"chat","id":...,"sender_id":...,"text":...,"timestamp":...}
    private func handleChatMessage(_ json: [String: Any]) {
        guard let text = json["text"] as? String else {
            return
        }
        
        // id 可能是 Int 或 String
        let id: String
        if let intId = json["id"] as? Int {
            id = String(intId)
        } else if let strId = json["id"] as? String {
            id = strId
        } else {
            id = UUID().uuidString
        }
        
        // sender_id 可能是 Int 或 String
        let senderId: String
        if let intSender = json["sender_id"] as? Int {
            senderId = String(intSender)
        } else if let strSender = json["sender_id"] as? String {
            senderId = strSender
        } else {
            senderId = ""
        }
        
        let timestamp: Date
        if let timestampStr = json["timestamp"] as? String {
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
    /// 後端格式：{"type":"sos","sender_id":...,"sender_name":...,"lat":...,"lng":...,"timestamp":...}
    private func handleSOSAlert(_ json: [String: Any]) {
        sosAlert = true
        
        if let lat = json["lat"] as? Double,
           let lng = json["lng"] as? Double {
            sosLocation = Location(
                latitude: lat,
                longitude: lng,
                timestamp: Date()
            )
        }
    }
    
    /// 處理對方螢幕狀態
    /// 後端格式：{"type":"screen_status","user_id":...,"screen_on":...,"text":...,"timestamp":...}
    private func handleScreenStatus(_ json: [String: Any]) {
        guard let screenOn = json["screen_on"] as? Bool else { return }
        
        let timestamp: Date
        if let timestampStr = json["timestamp"] as? String {
            timestamp = ISO8601DateFormatter().date(from: timestampStr) ?? Date()
        } else {
            timestamp = Date()
        }
        
        partnerScreenEvent = ScreenEvent(screenOn: screenOn, timestamp: timestamp)
        
        // 如果後端附帶了系統訊息文字，加入聊天列表
        if let text = json["text"] as? String {
            let msgId: String
            if let intId = json["message_id"] as? Int {
                msgId = String(intId)
            } else {
                msgId = UUID().uuidString
            }
            
            let systemMsg = ChatMessage(
                id: msgId,
                senderId: "system",
                text: text,
                timestamp: timestamp,
                isRead: false,
                messageType: .system
            )
            newMessage = systemMsg
            messages.append(systemMsg)
        }
    }
    
    /// 處理對方圍欄事件
    /// 後端格式：{"type":"geofence_event","user_id":...,"zone_name":...,"event":...,"text":...,"timestamp":...}
    private func handleGeofenceEventReceived(_ json: [String: Any]) {
        let timestamp: Date
        if let timestampStr = json["timestamp"] as? String {
            timestamp = ISO8601DateFormatter().date(from: timestampStr) ?? Date()
        } else {
            timestamp = Date()
        }
        
        // 加入聊天列表作為系統訊息
        if let text = json["text"] as? String {
            let msgId: String
            if let intId = json["message_id"] as? Int {
                msgId = String(intId)
            } else {
                msgId = UUID().uuidString
            }
            
            let systemMsg = ChatMessage(
                id: msgId,
                senderId: "system",
                text: text,
                timestamp: timestamp,
                isRead: false,
                messageType: .system
            )
            newMessage = systemMsg
            messages.append(systemMsg)
        }
        
        // 觸發圍欄事件通知（供 NotificationService 使用）
        let zoneName = json["zone_name"] as? String ?? ""
        let event = json["event"] as? String ?? ""
        let senderName = json["sender_name"] as? String ?? ""
        partnerGeofenceEvent = PartnerGeofenceEvent(
            zoneName: zoneName,
            event: event,
            senderName: senderName,
            timestamp: timestamp
        )
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
    
    /// 啟動心跳（每 25 秒 ping 一次）
    private func startHeartbeat() {
        stopHeartbeat()
        
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
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
    /// 背景模式下使用 beginBackgroundTask 保護重連過程
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
        
        // 使用 beginBackgroundTask 保護重連過程（App 在背景時）
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "WebSocketReconnect") {
            // 背景時間即將到期，結束任務
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.establishConnection()
                
                // 給連線建立一點時間，然後結束背景任務
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if bgTask != .invalid {
                        UIApplication.shared.endBackgroundTask(bgTask)
                        bgTask = .invalid
                    }
                }
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

// MARK: - 螢幕事件模型

/// 螢幕開關事件
struct ScreenEvent: Equatable, Sendable {
    let screenOn: Bool
    let timestamp: Date
}

/// 對方圍欄事件
struct PartnerGeofenceEvent: Equatable, Sendable {
    let zoneName: String
    let event: String  // "entry" or "exit"
    let senderName: String
    let timestamp: Date
}
