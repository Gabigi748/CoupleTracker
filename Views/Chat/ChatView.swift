// ChatView.swift
// CoupleTracker
//
// 簡易聊天頁面
// - 氣泡式訊息（自己右邊粉色，對方左邊紫色）
// - 底部輸入框 + 發送按鈕
// - 自動滾動到最新訊息

import SwiftUI

// MARK: - 聊天氣泡資料模型（僅供 UI 顯示用，避免與 Models/ChatMessage 衝突）
struct ChatBubbleData: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isMe: Bool           // true = 自己, false = 對方
    let timestamp: Date
}

struct ChatView: View {
    // MARK: - 狀態
    @State private var messageText = ""
    @State private var messages: [ChatBubbleData] = ChatBubbleData.sampleMessages
    
    @Environment(\.colorScheme) private var colorScheme
    
    // 時間格式化
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh-Hant")
        f.dateFormat = "HH:mm"
        return f
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // 聊天訊息列表
            messageList
            
            // 底部輸入區
            inputBar
        }
        .navigationTitle("💬 聊天")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - 訊息列表
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        MessageBubble(
                            message: message,
                            timeFormatter: timeFormatter,
                            colorScheme: colorScheme
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
                                ? Color.gray
                                : AppTheme.primaryGradient
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
        
        let newMessage = ChatBubbleData(
            text: trimmed,
            isMe: true,
            timestamp: Date()
        )
        
        withAnimation(.easeOut(duration: 0.2)) {
            messages.append(newMessage)
        }
        
        messageText = ""
        
        // TODO: 透過 FirebaseService 發送訊息
        // 模擬對方回覆
        simulateReply()
    }
    
    // 模擬對方回覆（假資料）
    private func simulateReply() {
        let replies = [
            "好的～ 💕",
            "我在路上了！",
            "等我一下 🥰",
            "想你了 ❤️",
            "晚餐想吃什麼？",
        ]
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let reply = ChatBubbleData(
                text: replies.randomElement() ?? "💕",
                isMe: false,
                timestamp: Date()
            )
            withAnimation(.easeOut(duration: 0.2)) {
                messages.append(reply)
            }
        }
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

// MARK: - 假資料
extension ChatBubbleData {
    static let sampleMessages: [ChatBubbleData] = {
        let calendar = Calendar.current
        let today = Date()
        
        return [
            ChatBubbleData(
                text: "早安～今天天氣好好 ☀️",
                isMe: false,
                timestamp: calendar.date(bySettingHour: 8, minute: 30, second: 0, of: today) ?? today
            ),
            ChatBubbleData(
                text: "早安寶貝！你起床了嗎？",
                isMe: true,
                timestamp: calendar.date(bySettingHour: 8, minute: 32, second: 0, of: today) ?? today
            ),
            ChatBubbleData(
                text: "剛起來～準備出門了",
                isMe: false,
                timestamp: calendar.date(bySettingHour: 8, minute: 35, second: 0, of: today) ?? today
            ),
            ChatBubbleData(
                text: "路上小心喔 💕",
                isMe: true,
                timestamp: calendar.date(bySettingHour: 8, minute: 36, second: 0, of: today) ?? today
            ),
            ChatBubbleData(
                text: "中午一起吃飯嗎？",
                isMe: false,
                timestamp: calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today) ?? today
            ),
            ChatBubbleData(
                text: "好啊！想吃什麼？",
                isMe: true,
                timestamp: calendar.date(bySettingHour: 11, minute: 2, second: 0, of: today) ?? today
            ),
            ChatBubbleData(
                text: "我想吃拉麵 🍜",
                isMe: false,
                timestamp: calendar.date(bySettingHour: 11, minute: 3, second: 0, of: today) ?? today
            ),
            ChatBubbleData(
                text: "那去上次那家！我 12 點到",
                isMe: true,
                timestamp: calendar.date(bySettingHour: 11, minute: 5, second: 0, of: today) ?? today
            ),
        ]
    }()
}

// MARK: - Preview
#Preview("聊天頁面") {
    NavigationStack {
        ChatView()
    }
}

#Preview("深色模式") {
    NavigationStack {
        ChatView()
    }
    .preferredColorScheme(.dark)
}
