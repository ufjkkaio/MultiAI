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
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            MessageRow(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
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
                let (bytes, urlResponse) = try await URLSession.shared.bytes(for: req)
                let http = urlResponse as? HTTPURLResponse

                if http?.statusCode == 403 {
                    var data = Data()
                    for try await byte in bytes { data.append(byte) }
                    let err = try? JSONDecoder().decode(ErrorBody.self, from: data)
                    await MainActor.run {
                        errorMessage = err?.error ?? "サブスクリプションが必要です"
                        isSending = false
                    }
                    return
                }
                if http?.statusCode == 429 {
                    for try await _ in bytes {}
                    await MainActor.run {
                        errorMessage = "今月の利用上限に達しました"
                        isSending = false
                    }
                    return
                }

                guard http?.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true else {
                    var data = Data()
                    for try await byte in bytes { data.append(byte) }
                    let res = try JSONDecoder().decode(SendMessageResponse.self, from: data)
                    await MainActor.run {
                        messages.append(Message(id: UUID().uuidString, role: "user", provider: nil, content: res.userMessage.content, createdAt: nil))
                        messages.append(contentsOf: res.assistantMessages)
                        isSending = false
                    }
                    return
                }

                var buffer = Data()
                for try await byte in bytes {
                    buffer.append(byte)
                    while let str = String(data: buffer, encoding: .utf8),
                          let range = str.range(of: "\n\n") {
                        let event = String(str[..<range.lowerBound])
                        let rest = String(str[range.upperBound...])
                        buffer = Data(rest.utf8)
                        await processSSEEvent(event)
                    }
                }
                await MainActor.run { isSending = false }
            } catch {
                await MainActor.run {
                    errorMessage = "送信に失敗しました"
                    isSending = false
                }
            }
        }
    }

    private func processSSEEvent(_ raw: String) async {
        var eventType = ""
        var dataStr = ""
        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("event: ") {
                eventType = String(line.dropFirst(7))
            } else if line.hasPrefix("data: ") {
                dataStr = String(line.dropFirst(6))
            }
        }
        guard let data = dataStr.data(using: .utf8) else { return }
        await MainActor.run {
            switch eventType {
            case "user":
                if let u = try? JSONDecoder().decode(UserMessagePart.self, from: data) {
                    let newMsg = Message(id: UUID().uuidString, role: "user", provider: nil, content: u.content, createdAt: nil)
                    messages = messages + [newMsg]
                }
            case "message":
                let dec = JSONDecoder()
                dec.keyDecodingStrategy = .convertFromSnakeCase
                if let m = try? dec.decode(Message.self, from: data) {
                    messages = messages + [m]  // 再代入で SwiftUI の更新を確実に
                }
            case "error":
                if let e = try? JSONDecoder().decode(ProviderError.self, from: data) {
                    errorMessage = "\(e.provider): \(e.error)"
                }
            case "done":
                // SSE で届かないメッセージがある場合に備え、サーバーから再取得して確実に表示
                loadMessages()
            default:
                break
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
