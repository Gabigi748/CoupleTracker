// FirebaseService.swift
// CoupleTracker
//
// Firebase 服務 — 處理 Auth、Firestore 讀寫、配對系統、即時監聽

import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

/// Firebase 服務管理器
/// 統一管理所有 Firebase 操作：認證、資料庫、配對、即時同步
@Observable
final class FirebaseService {
    
    // MARK: - 屬性
    
    /// 當前登入用戶
    var currentUser: AppUser?
    
    /// 配對對象資料
    var partner: AppUser?
    
    /// 對方即時位置
    var partnerLocation: Location?
    
    /// 聊天訊息列表
    var messages: [ChatMessage] = []
    
    /// 是否正在載入
    var isLoading: Bool = false
    
    /// 錯誤訊息
    var errorMessage: String?
    
    /// 是否已登入
    var isAuthenticated: Bool {
        Auth.auth().currentUser != nil
    }
    
    // MARK: - 私有屬性
    
    /// Firestore 資料庫參考
    private let db = Firestore.firestore()
    
    /// 對方位置的即時監聽器
    private var partnerLocationListener: ListenerRegistration?
    
    /// 聊天訊息監聽器
    private var messagesListener: ListenerRegistration?
    
    // MARK: - 初始化
    
    init() {
        // 監聽 Auth 狀態變化
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if let user {
                    await self?.fetchCurrentUser(uid: user.uid)
                } else {
                    self?.currentUser = nil
                    self?.partner = nil
                    self?.removeListeners()
                }
            }
        }
    }
    
    deinit {
        removeListeners()
    }
    
    // MARK: - 認證（Auth）
    
    /// Email 註冊
    /// - Parameters:
    ///   - email: 用戶 Email
    ///   - password: 密碼
    ///   - name: 顯示名稱
    func signUp(email: String, password: String, name: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let uid = result.user.uid
        
        // 建立用戶文件
        let newUser = AppUser.newUser(uid: uid, name: name, email: email)
        try await saveUser(newUser)
        currentUser = newUser
    }
    
    /// Email 登入
    /// - Parameters:
    ///   - email: 用戶 Email
    ///   - password: 密碼
    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        await fetchCurrentUser(uid: result.user.uid)
    }
    
    /// 登出
    func signOut() throws {
        try Auth.auth().signOut()
        currentUser = nil
        partner = nil
        removeListeners()
    }
    
    // MARK: - 用戶資料（Firestore）
    
    /// 取得當前用戶資料
    private func fetchCurrentUser(uid: String) async {
        do {
            let document = try await db.collection("users").document(uid).getDocument()
            currentUser = try document.data(as: AppUser.self)
            
            // 如果已配對，開始監聽對方
            if let partnerUid = currentUser?.partnerUid {
                startListeningToPartner(uid: partnerUid)
            }
        } catch {
            errorMessage = "無法取得用戶資料：\(error.localizedDescription)"
        }
    }
    
    /// 儲存用戶資料到 Firestore
    private func saveUser(_ user: AppUser) async throws {
        try db.collection("users").document(user.uid).setData(from: user)
    }
    
    /// 更新用戶位置
    /// - Parameter location: 新的位置資料
    func updateLocation(_ location: Location) async throws {
        guard let uid = currentUser?.uid else { return }
        
        // 更新用戶文件中的位置
        try db.collection("users").document(uid).updateData([
            "location": [
                "id": location.id,
                "latitude": location.latitude,
                "longitude": location.longitude,
                "timestamp": Timestamp(date: location.timestamp),
                "address": location.address as Any
            ],
            "last_updated": Timestamp(date: Date())
        ])
        
        // 同時寫入位置歷史
        try db.collection("users").document(uid)
            .collection("location_history")
            .document(location.id)
            .setData(from: location)
        
        currentUser?.location = location
        currentUser?.lastUpdated = Date()
    }
    
    /// 同步電量資訊
    /// - Parameter level: 電量百分比（0-100）
    func updateBatteryLevel(_ level: Int) async throws {
        guard let uid = currentUser?.uid else { return }
        
        try await db.collection("users").document(uid).updateData([
            "battery_level": level
        ])
        
        currentUser?.batteryLevel = level
    }
    
    // MARK: - 配對系統
    
    /// 生成 6 位配對碼
    /// - Returns: 生成的配對碼
    func generatePairingCode() async throws -> String {
        guard let uid = currentUser?.uid else {
            throw CoupleTrackerError.notAuthenticated
        }
        
        // 生成 6 位隨機數字碼
        let code = String(format: "%06d", Int.random(in: 0...999999))
        
        // 儲存到用戶文件
        try await db.collection("users").document(uid).updateData([
            "pairing_code": code
        ])
        
        // 同時寫入配對碼索引（方便查詢）
        try await db.collection("pairing_codes").document(code).setData([
            "uid": uid,
            "created_at": Timestamp(date: Date()),
            // 配對碼 24 小時後過期
            "expires_at": Timestamp(date: Date().addingTimeInterval(86400))
        ])
        
        currentUser?.pairingCode = code
        return code
    }
    
    /// 驗證配對碼並綁定情侶
    /// - Parameter code: 對方的 6 位配對碼
    func verifyAndPair(code: String) async throws {
        guard let myUid = currentUser?.uid else {
            throw CoupleTrackerError.notAuthenticated
        }
        
        // 查詢配對碼
        let document = try await db.collection("pairing_codes").document(code).getDocument()
        
        guard let data = document.data(),
              let partnerUid = data["uid"] as? String else {
            throw CoupleTrackerError.invalidPairingCode
        }
        
        // 檢查是否過期
        if let expiresAt = data["expires_at"] as? Timestamp,
           expiresAt.dateValue() < Date() {
            throw CoupleTrackerError.pairingCodeExpired
        }
        
        // 不能跟自己配對
        guard partnerUid != myUid else {
            throw CoupleTrackerError.cannotPairWithSelf
        }
        
        // 執行配對：雙方互相綁定
        let batch = db.batch()
        
        // 更新自己的 partnerUid
        let myRef = db.collection("users").document(myUid)
        batch.updateData(["partner_uid": partnerUid], forDocument: myRef)
        
        // 更新對方的 partnerUid
        let partnerRef = db.collection("users").document(partnerUid)
        batch.updateData(["partner_uid": myUid], forDocument: partnerRef)
        
        // 刪除已使用的配對碼
        let codeRef = db.collection("pairing_codes").document(code)
        batch.deleteDocument(codeRef)
        
        try await batch.commit()
        
        // 更新本地狀態
        currentUser?.partnerUid = partnerUid
        
        // 開始監聽對方
        startListeningToPartner(uid: partnerUid)
    }
    
    /// 解除配對
    func unpair() async throws {
        guard let myUid = currentUser?.uid,
              let partnerUid = currentUser?.partnerUid else { return }
        
        let batch = db.batch()
        
        let myRef = db.collection("users").document(myUid)
        batch.updateData(["partner_uid": FieldValue.delete()], forDocument: myRef)
        
        let partnerRef = db.collection("users").document(partnerUid)
        batch.updateData(["partner_uid": FieldValue.delete()], forDocument: partnerRef)
        
        try await batch.commit()
        
        currentUser?.partnerUid = nil
        partner = nil
        partnerLocation = nil
        removeListeners()
    }
    
    // MARK: - 即時監聽
    
    /// 開始即時監聽對方位置
    /// - Parameter uid: 對方的 UID
    private func startListeningToPartner(uid: String) {
        // 移除舊的監聽器
        partnerLocationListener?.remove()
        
        // 監聽對方用戶文件的變化
        partnerLocationListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot, snapshot.exists else { return }
                
                do {
                    let partnerUser = try snapshot.data(as: AppUser.self)
                    Task { @MainActor in
                        self.partner = partnerUser
                        self.partnerLocation = partnerUser.location
                    }
                } catch {
                    Task { @MainActor in
                        self.errorMessage = "解析對方資料失敗：\(error.localizedDescription)"
                    }
                }
            }
    }
    
    // MARK: - 聊天訊息
    
    /// 開始監聽聊天訊息
    func startListeningToMessages() {
        guard let myUid = currentUser?.uid,
              let partnerUid = currentUser?.partnerUid else { return }
        
        // 聊天室 ID：兩人 UID 排序後組合（確保唯一）
        let chatId = [myUid, partnerUid].sorted().joined(separator: "_")
        
        messagesListener?.remove()
        messagesListener = db.collection("chats").document(chatId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .limit(toLast: 100)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot else { return }
                
                let newMessages = snapshot.documents.compactMap { doc in
                    try? doc.data(as: ChatMessage.self)
                }
                
                Task { @MainActor in
                    self.messages = newMessages
                }
            }
    }
    
    /// 發送聊天訊息
    /// - Parameter text: 訊息文字
    func sendMessage(_ text: String) async throws {
        guard let myUid = currentUser?.uid,
              let partnerUid = currentUser?.partnerUid else {
            throw CoupleTrackerError.notPaired
        }
        
        let chatId = [myUid, partnerUid].sorted().joined(separator: "_")
        let message = ChatMessage.textMessage(senderId: myUid, text: text)
        
        try db.collection("chats").document(chatId)
            .collection("messages")
            .document(message.id)
            .setData(from: message)
    }
    
    /// 發送 SOS 緊急訊息
    /// - Parameter location: 當前位置
    func sendSOSMessage(location: Location?) async throws {
        guard let myUid = currentUser?.uid,
              let partnerUid = currentUser?.partnerUid else {
            throw CoupleTrackerError.notPaired
        }
        
        let chatId = [myUid, partnerUid].sorted().joined(separator: "_")
        let message = ChatMessage.sosMessage(senderId: myUid, location: location)
        
        try db.collection("chats").document(chatId)
            .collection("messages")
            .document(message.id)
            .setData(from: message)
    }
    
    // MARK: - 清理
    
    /// 移除所有監聽器
    private func removeListeners() {
        partnerLocationListener?.remove()
        partnerLocationListener = nil
        messagesListener?.remove()
        messagesListener = nil
    }
}

// MARK: - 錯誤定義

/// CoupleTracker 自定義錯誤
enum CoupleTrackerError: LocalizedError {
    case notAuthenticated
    case notPaired
    case invalidPairingCode
    case pairingCodeExpired
    case cannotPairWithSelf
    case geofenceLimitReached
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "尚未登入"
        case .notPaired:
            return "尚未配對"
        case .invalidPairingCode:
            return "配對碼無效"
        case .pairingCodeExpired:
            return "配對碼已過期"
        case .cannotPairWithSelf:
            return "不能與自己配對"
        case .geofenceLimitReached:
            return "已達到圍欄數量上限"
        }
    }
}
