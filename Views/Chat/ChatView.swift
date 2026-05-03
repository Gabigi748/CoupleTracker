// ChatView.swift
// CoupleTracker
//
// 聊天頁面
// - 氣泡式訊息（自己右邊粉色，對方左邊紫色）
// - 底部輸入框 + 發送按鈕
// - 自動滾動到最新訊息
// - 透過 WebSocketManager 收發即時訊息

import SwiftUI

struct ChatView: View {
    // MARK: - 狀態
    @State private var messageText = ""
    @State private var messages: [ChatBubbleData] = []
    @State private var isLoadingHistory = true
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(WebSocketManager.self) private var webSocketManager
    @Environment(APIService.self) private var apiService
    
    // 當前用戶 ID
    private var myUserId: String {
        apiService.currentUser?.uid ?? ""
    }
    
    // 時間格式化
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh-Hant")
        f.dateFormat = "HH:mm"
        return f
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoadingHistory {
                ProgressView("載入聊天記錄...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 聊天訊息列表
                messageList
            }
            
            // 底部輸入區
            inputBar
        }
        .navigationTitle("💬 聊天")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadChatHistory()
        }
        .onChange(of: webSocketManager.newMessage) { _, newMsg in
            // 收到新的即時訊息
            guard let msg = newMsg else { return }
            let bubble = ChatBubbleData(
                id: msg.id,
                text: msg.text,
                isMe: msg.senderId == myUserId,
                timestamp: msg.timestamp,
                messageType: msg.messageType
            )
            withAnimation(.easeOut(duration: 0.2)) {
                messages.append(bubble)
            }
        }
    }
    
    // MARK: - 載入聊天歷史
    private func loadChatHistory() async {
        do {
            let history = try await apiService.getChatHistory(page: 1)
            messages = history.map { msg in
                ChatBubbleData(
                    id: msg.id,
                    text: msg.text,
                    isMe: msg.senderId == myUserId,
                    timestamp: msg.timestamp,
                    messageType: msg.messageType
                )
            }
        } catch {
            // 載入失敗，顯示空列表
            messages = []
        }
        isLoadingHistory = false
    }
    
    // MARK: - 訊息列表
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        if message.isSystem {
                            // 系統訊息：居中、灰色小字
                            SystemMessageBubble(message: message, timeFormatter: timeFormatter)
                                .id(message.id)
                        } else {
                            MessageBubble(
                                message: message,
                                timeFormatter: timeFormatter,
                                colorScheme: colorScheme
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .onChange(of: messages.count) { _, _ in
                // 自動滾動到最新訊息
                if let lastMessage = messages.last {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onAppear {
                // 初始滾動到底部
                if let lastMessage = messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
    
    // MARK: - 底部輸入區
    private var inputBar: some View {
        HStack(spacing: 12) {
            // 文字輸入框
            TextField("輸入訊息...", text: $messageText, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(colorScheme == .dark
                              ? Color(.systemGray5)
                              : Color(.systemGray6))
                )
            
            // 發送按鈕
            Button {
                sendMessage()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(
                                messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? AnyShapeStyle(Color.gray)
                                : AnyShapeStyle(AppTheme.primaryGradient)
                            )
                    )
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 4, y: -2)
        )
    }
    
    // MARK: - 發送訊息
    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // 立即在本地顯示（樂觀更新）
        let newMessage = ChatBubbleData(
            id: UUID().uuidString,
            text: trimmed,
            isMe: true,
            timestamp: Date()
        )
        
        withAnimation(.easeOut(duration: 0.2)) {
            messages.append(newMessage)
        }
        
        messageText = ""
        
        // 透過 WebSocket 發送
        webSocketManager.sendChat(trimmed)
    }
}

// MARK: - 聊天氣泡資料模型
struct ChatBubbleData: Identifiable, Equatable {
    let id: String
    let text: String
    let isMe: Bool           // true = 自己, false = 對方
    let timestamp: Date
    let messageType: MessageType  // 訊息類型
    
    /// 是否為系統訊息
    var isSystem: Bool { messageType == .system }
    
    init(id: String = UUID().uuidString, text: String, isMe: Bool, timestamp: Date, messageType: MessageType = .text) {
        self.id = id
        self.text = text
        self.isMe = isMe
        self.timestamp = timestamp
        self.messageType = messageType
    }
}

// MARK: - 訊息氣泡元件
struct MessageBubble: View {
    let message: ChatBubbleData
    let timeFormatter: DateFormatter
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isMe {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isMe ? .trailing : .leading, spacing: 4) {
                // 訊息氣泡
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.isMe ? .white : (colorScheme == .dark ? .white : .primary))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                
                // 時間戳
                Text(timeFormatter.string(from: message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            
            if !message.isMe {
                Spacer(minLength: 60)
            }
        }
    }
    
    // 氣泡背景
    private var bubbleBackground: some View {
        Group {
            if message.isMe {
                // 自己的訊息：粉色漸層
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.pink, AppTheme.pink.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            } else {
                // 對方的訊息：紫色
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        colorScheme == .dark
                        ? AppTheme.purple.opacity(0.3)
                        : AppTheme.softPurple.opacity(0.5)
                    )
            }
        }
    }
}

// MARK: - 系統訊息元件（居中、灰色小字、不顯示頭像）
struct SystemMessageBubble: View {
    let message: ChatBubbleData
    let timeFormatter: DateFormatter
    
    var body: some View {
        VStack(spacing: 4) {
            Text(message.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(.systemGray5).opacity(0.6))
                )
            
            Text(timeFormatter.string(from: message.timestamp))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

// MARK: - Preview
#Preview("聊天頁面") {
    NavigationStack {
        ChatView()
            .environment(WebSocketManager())
            .environment(APIService())
    }
}

#Preview("深色模式") {
    NavigationStack {
        ChatView()
            .environment(WebSocketManager())
            .environment(APIService())
    }
    .preferredColorScheme(.dark)
}
