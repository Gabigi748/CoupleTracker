// APIService.swift
// CoupleTracker
//
// API 服務 — 處理認證、配對、位置歷史、聊天歷史、圍欄 CRUD
// 使用 URLSession + async/await 呼叫自建後端 REST API
// JWT Token 存放於 Keychain

import Foundation
import Observation
import Security
import UIKit

/// API 服務管理器
/// 統一管理所有後端 API 操作：認證、配對、位置歷史、圍欄 CRUD
@MainActor
@Observable
final class APIService {
    
    // MARK: - 公開屬性
    
    /// 是否已登入
    var isAuthenticated: Bool = false
    
    /// 當前登入用戶
    var currentUser: AppUser?
    
    /// 配對對象資料
    var partnerUser: AppUser?
    
    /// 是否正在載入
    var isLoading: Bool = false
    
    /// 錯誤訊息
    var errorMessage: String?
    
    // MARK: - 私有屬性
    
    /// 後端 API Base URL
    private let baseURL = "https://anzufish.org/couple-api"
    
    /// JWT Token（從 Keychain 讀取）
    private var token: String?
    
    /// URLSession 實例
    private let session: URLSession
    
    /// Keychain 存取的 service 名稱
    private static let keychainService = "org.anzufish.coupletracker"
    
    /// Keychain 存取的 account 名稱
    private static let keychainAccount = "jwt_token"
    
    // MARK: - 初始化
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        
        // 嘗試從 Keychain 恢復 Token
        if let savedToken = Self.loadTokenFromKeychain() {
            self.token = savedToken
            self.isAuthenticated = true
            // 驗證 Token 是否仍有效
            Task {
                await restoreSession()
            }
        }
    }
    
    // MARK: - 認證 API
    
    /// 註冊新帳號
    /// - Parameters:
    ///   - email: 用戶 Email
    ///   - password: 密碼
    ///   - name: 顯示名稱
    func register(email: String, password: String, name: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "name": name
        ]
        
        let response: AuthResponse = try await request(
            method: "POST",
            path: "/api/auth/register",
            body: body
        )
        
        // 儲存 Token 到 Keychain
        token = response.token
        Self.saveTokenToKeychain(response.token)
        
        currentUser = response.user
        isAuthenticated = true
    }
    
    /// 登入
    /// - Parameters:
    ///   - email: 用戶 Email
    ///   - password: 密碼
    func login(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let body: [String: Any] = [
            "email": email,
            "password": password
        ]
        
        let response: AuthResponse = try await request(
            method: "POST",
            path: "/api/auth/login",
            body: body
        )
        
        // 儲存 Token 到 Keychain
        token = response.token
        Self.saveTokenToKeychain(response.token)
        
        currentUser = response.user
        isAuthenticated = true
        
        // 取得配對對象資料
        if response.user.partnerUid != nil {
            await fetchPartner()
        }
    }
    
    /// 登出
    func logout() {
        token = nil
        Self.deleteTokenFromKeychain()
        currentUser = nil
        partnerUser = nil
        isAuthenticated = false
    }
    
    /// 取得當前用戶資料
    func fetchCurrentUser() async throws {
        let user: AppUser = try await request(
            method: "GET",
            path: "/api/auth/me"
        )
        currentUser = user
        
        if user.partnerUid != nil {
            await fetchPartner()
        }
    }
    
    // MARK: - 個人資料 API
    
    /// 更新個人資料（名稱）
    func updateProfile(name: String) async throws {
        let body: [String: Any] = ["name": name]
        let _: AppUser = try await request(
            method: "PUT",
            path: "/api/auth/profile",
            body: body
        )
        currentUser?.name = name
    }
    
    // MARK: - 配對 API
    
    /// 生成配對碼
    /// - Returns: 6 位配對碼
    @discardableResult
    func generatePairCode() async throws -> String {
        let response: PairCodeResponse = try await request(
            method: "POST",
            path: "/api/pair/generate"
        )
        currentUser?.pairingCode = response.code
        return response.code
    }
    
    /// 使用配對碼連結
    /// - Parameter code: 對方的 6 位配對碼
    func connectWithCode(_ code: String) async throws {
        let body: [String: Any] = ["code": code]
        
        let response: PairStatusResponse = try await request(
            method: "POST",
            path: "/api/pair/connect",
            body: body
        )
        
        currentUser?.partnerUid = response.partnerUid
        partnerUser = response.partner
    }
    
    /// 解除配對
    func unpair() async throws {
        let _: EmptyResponse = try await request(
            method: "DELETE",
            path: "/api/pair"
        )
        
        currentUser?.partnerUid = nil
        partnerUser = nil
    }
    
    /// 取得配對狀態
    func getPairStatus() async throws -> PairStatusResponse {
        let response: PairStatusResponse = try await request(
            method: "GET",
            path: "/api/pair/status"
        )
        
        if let partner = response.partner {
            partnerUser = partner
        }
        
        return response
    }
    
    // MARK: - 位置歷史 API
    
    /// 取得位置歷史
    /// - Parameters:
    ///   - from: 起始時間
    ///   - to: 結束時間
    /// - Returns: 位置歷史陣列
    func getLocationHistory(from: Date, to: Date) async throws -> [Location] {
        let fromStr = ISO8601DateFormatter().string(from: from)
        let toStr = ISO8601DateFormatter().string(from: to)
        
        let locations: [Location] = try await request(
            method: "GET",
            path: "/api/locations/history?from=\(fromStr)&to=\(toStr)"
        )
        
        return locations
    }
    
    // MARK: - 聊天歷史 API
    
    /// 取得聊天歷史
    /// - Parameter page: 頁碼（分頁）
    /// - Returns: 聊天訊息陣列
    func getChatHistory(page: Int = 1) async throws -> [ChatMessage] {
        let messages: [ChatMessage] = try await request(
            method: "GET",
            path: "/api/chat/history?page=\(page)"
        )
        return messages
    }
    
    // MARK: - SOS API
    
    /// 發送 SOS 緊急求助
    /// - Parameters:
    ///   - latitude: 緯度
    ///   - longitude: 經度
    func sendSOS(latitude: Double, longitude: Double) async throws {
        let body: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude
        ]
        
        let _: EmptyResponse = try await request(
            method: "POST",
            path: "/api/sos",
            body: body
        )
    }
    
    // MARK: - 圍欄 CRUD API
    
    /// 取得所有圍欄
    /// - Returns: 圍欄陣列
    func getGeofences() async throws -> [GeofenceZone] {
        let zones: [GeofenceZone] = try await request(
            method: "GET",
            path: "/api/geofences"
        )
        return zones
    }
    
    /// 新增圍欄
    /// - Parameter zone: 要新增的圍欄
    /// - Returns: 新增後的圍欄（含伺服器生成的 ID）
    @discardableResult
    func createGeofence(_ zone: GeofenceZone) async throws -> GeofenceZone {
        let body: [String: Any] = [
            "name": zone.name,
            "latitude": zone.latitude,
            "longitude": zone.longitude,
            "radius": zone.radius,
            "notify_on_entry": zone.notifyOnEntry,
            "notify_on_exit": zone.notifyOnExit
        ]
        
        let created: GeofenceZone = try await request(
            method: "POST",
            path: "/api/geofences",
            body: body
        )
        return created
    }
    
    /// 更新圍欄
    /// - Parameter zone: 更新後的圍欄
    func updateGeofence(_ zone: GeofenceZone) async throws {
        let body: [String: Any] = [
            "name": zone.name,
            "radius": zone.radius,
            "notify_on_entry": zone.notifyOnEntry,
            "notify_on_exit": zone.notifyOnExit
        ]
        
        let _: EmptyResponse = try await request(
            method: "PUT",
            path: "/api/geofences/\(zone.id)",
            body: body
        )
    }
    
    /// 刪除圍欄
    /// - Parameter zoneId: 圍欄 ID
    func deleteGeofence(_ zoneId: String) async throws {
        let _: EmptyResponse = try await request(
            method: "DELETE",
            path: "/api/geofences/\(zoneId)"
        )
    }
    
    // MARK: - APNs Token 上傳
    
    /// 上傳 APNs Device Token 到後端
    /// - Parameter deviceToken: APNs token 字串
    func uploadAPNsToken(_ deviceToken: String) async throws {
        let body: [String: Any] = [
            "token": deviceToken,
            "platform": "ios"
        ]
        
        let _: EmptyResponse = try await request(
            method: "POST",
            path: "/api/notifications/token",
            body: body
        )
    }
    
    // MARK: - 電量同步
    
    /// 更新電量資訊
    /// - Parameter level: 電量百分比（0-100）
    func updateBatteryLevel(_ level: Int) async throws {
        let body: [String: Any] = ["battery_level": level]
        
        let _: EmptyResponse = try await request(
            method: "PUT",
            path: "/api/auth/battery",
            body: body
        )
        
        currentUser?.batteryLevel = level
    }
    
    // MARK: - Token 存取
    
    /// 取得當前 JWT Token（供 WebSocketManager 使用）
    var currentToken: String? {
        token
    }
    
    // MARK: - 私有方法
    
    /// 恢復登入狀態（App 啟動時驗證 Token）
    private func restoreSession() async {
        do {
            try await fetchCurrentUser()
        } catch {
            // Token 無效，清除登入狀態
            logout()
        }
    }
    
    /// 取得配對對象資料
    private func fetchPartner() async {
        do {
            let status = try await getPairStatus()
            partnerUser = status.partner
        } catch {
            errorMessage = "無法取得對方資料：\(error.localizedDescription)"
        }
    }
    
    /// 通用 API 請求方法
    /// - Parameters:
    ///   - method: HTTP 方法（GET/POST/PUT/DELETE）
    ///   - path: API 路徑
    ///   - body: 請求 body（可選）
    /// - Returns: 解碼後的回應物件
    private func request<T: Decodable>(
        method: String,
        path: String,
        body: [String: Any]? = nil
    ) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw CoupleTrackerError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 附加 JWT Token
        if let token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // 設定 body
        if let body {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        // 發送請求
        let (data, response) = try await session.data(for: urlRequest)
        
        // 檢查 HTTP 狀態碼
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CoupleTrackerError.networkError("無效的回應")
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            // 成功 — 解析 API 包裝格式 {"success":true,"data":{...}}
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let wrapper = try decoder.decode(APIResponse<T>.self, from: data)
            guard let result = wrapper.data else {
                throw CoupleTrackerError.serverError(wrapper.error ?? "回應資料為空")
            }
            return result
            
        case 401:
            // Token 過期或無效
            logout()
            throw CoupleTrackerError.notAuthenticated
            
        case 400:
            // 請求錯誤，解析後端錯誤訊息
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw CoupleTrackerError.validationError(errorResponse.errorMessage)
            }
            throw CoupleTrackerError.validationError("請求資料有誤")
            
        case 404:
            throw CoupleTrackerError.notFound
            
        case 409:
            throw CoupleTrackerError.conflict
            
        case 422:
            // 驗證錯誤，嘗試解析錯誤訊息
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw CoupleTrackerError.validationError(errorResponse.errorMessage)
            }
            throw CoupleTrackerError.validationError("請求資料有誤")
            
        default:
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw CoupleTrackerError.serverError(errorResponse.errorMessage)
            }
            throw CoupleTrackerError.serverError("伺服器錯誤（\(httpResponse.statusCode)）")
        }
    }
    
    // MARK: - Keychain 操作
    
    /// 儲存 Token 到 Keychain
    private static func saveTokenToKeychain(_ token: String) {
        // 先刪除舊的
        deleteTokenFromKeychain()
        
        guard let data = token.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemAdd(query as CFDictionary, nil)
    }
    
    /// 從 Keychain 讀取 Token
    private static func loadTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return token
    }
    
    /// 從 Keychain 刪除 Token
    private static func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - API 回應模型

/// 通用 API 回應包裝
struct APIResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: String?
}

/// 認證回應
struct AuthResponse: Codable {
    let token: String
    let user: AppUser
}

/// 配對碼回應
struct PairCodeResponse: Codable {
    let code: String
    let expiresAt: Date?
}

/// 配對狀態回應
struct PairStatusResponse: Codable {
    let isPaired: Bool
    let partnerUid: String?
    let partner: AppUser?
}

/// 空回應（用於不需要回傳資料的 API）
struct EmptyResponse: Codable {}

/// 錯誤回應
struct ErrorResponse: Codable {
    let error: String?
    let message: String?
    
    /// 取得錯誤訊息（相容 error 和 message 兩種格式）
    var errorMessage: String {
        error ?? message ?? "未知錯誤"
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
    case invalidURL
    case networkError(String)
    case serverError(String)
    case validationError(String)
    case notFound
    case conflict
    
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
        case .invalidURL:
            return "無效的 URL"
        case .networkError(let msg):
            return "網路錯誤：\(msg)"
        case .serverError(let msg):
            return "伺服器錯誤：\(msg)"
        case .validationError(let msg):
            return "驗證錯誤：\(msg)"
        case .notFound:
            return "找不到資源"
        case .conflict:
            return "資源衝突"
        }
    }
}
