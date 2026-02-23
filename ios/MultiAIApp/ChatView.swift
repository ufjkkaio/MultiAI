import SwiftUI

struct ChatView: View {
    let roomId: String
    @EnvironmentObject var appState: AppState
    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            MessageRow(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            
            HStack(spacing: 8) {
                TextField("メッセージ", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                Button("送信") {
                    sendMessage()
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding()
        }
        .onAppear { loadMessages() }
    }
    
    private func loadMessages() {
        guard let token = appState.authToken else { return }
        guard let url = URL(string: APIClient.baseURL + "/chat/rooms/\(roomId)/messages") else { return }
        var req = URLRequest(url: url)
        req.allHTTPHeaderFields = APIClient.authHeader(token)
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let res = try JSONDecoder().decode(MessagesResponse.self, from: data)
                await MainActor.run {
                    messages = res.messages
                    errorMessage = nil
                }
            } catch {
                await MainActor.run { errorMessage = "履歴の読み込みに失敗しました" }
            }
        }
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let token = appState.authToken else { return }
        
        guard let url = URL(string: APIClient.baseURL + "/chat/rooms/\(roomId)/messages") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.allHTTPHeaderFields = APIClient.authHeader(token)
        req.httpBody = try? JSONEncoder().encode(["content": text])
        
        isSending = true
        inputText = ""
        errorMessage = nil
        
        Task {
            do {
                let (data, urlResponse) = try await URLSession.shared.data(for: req)
                let http = urlResponse as? HTTPURLResponse
                
                if http?.statusCode == 403 {
                    let err = try? JSONDecoder().decode(ErrorBody.self, from: data)
                    await MainActor.run {
                        errorMessage = err?.error ?? "サブスクリプションが必要です"
                        isSending = false
                    }
                    return
                }
                if http?.statusCode == 429 {
                    await MainActor.run {
                        errorMessage = "今月の利用上限に達しました"
                        isSending = false
                    }
                    return
                }
                
                let res = try JSONDecoder().decode(SendMessageResponse.self, from: data)
                await MainActor.run {
                    messages.append(Message(
                        id: UUID().uuidString,
                        role: "user",
                        provider: nil,
                        content: res.userMessage.content,
                        createdAt: nil
                    ))
                    messages.append(contentsOf: res.assistantMessages)
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "送信に失敗しました"
                    isSending = false
                }
            }
        }
    }
}

struct MessageRow: View {
    let message: Message
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == "user" {
                Spacer(minLength: 40)
            } else {
                Text(providerLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(message.content)
                .padding(10)
                .background(message.role == "user" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                .cornerRadius(12)
            if message.role != "user" {
                Spacer(minLength: 40)
            }
        }
    }
    
    private var providerLabel: String {
        switch message.provider {
        case "openai": return "ChatGPT"
        case "gemini": return "Gemini"
        default: return ""
        }
    }
}

struct MessagesResponse: Codable {
    let messages: [Message]
}

struct ErrorBody: Codable {
    let error: String?
}
