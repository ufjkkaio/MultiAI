import SwiftUI

struct ChatView: View {
    let roomId: String
    var roomName: String?
    var onRoomUpdated: (() -> Void)?

    @EnvironmentObject var appState: AppState
    @State private var displayName: String
    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool
    @State private var showEditNameSheet = false

    init(roomId: String, roomName: String? = nil, onRoomUpdated: (() -> Void)? = nil) {
        self.roomId = roomId
        self.roomName = roomName
        self.onRoomUpdated = onRoomUpdated
        _displayName = State(initialValue: Self.displayName(from: roomName, roomId: roomId))
    }

    private static func displayName(from name: String?, roomId: String) -> String {
        if let n = name, !n.isEmpty { return n }
        return String(roomId.prefix(8)) + "..."
    }

    var body: some View {
        VStack(spacing: 0) {
            messagesArea
            if let err = errorMessage {
                errorBanner(err)
            }
            inputArea
        }
        .background(AppTheme.background)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditNameSheet = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.light)
        .onAppear { loadMessages() }
        .sheet(isPresented: $showEditNameSheet) {
            EditRoomNameSheet(
                currentName: displayName,
                onSave: { newName in
                    displayName = newName.isEmpty ? String(roomId.prefix(8)) + "..." : newName
                    showEditNameSheet = false
                    updateRoomName(newName)
                    onRoomUpdated?()
                },
                onCancel: { showEditNameSheet = false }
            )
        }
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { msg in
                        MessageRow(message: msg)
                            .id(msg.id)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    isInputFocused = false
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.errorRed)
            Text(text)
                .font(AppTheme.captionFont)
                .foregroundStyle(AppTheme.errorRed)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.errorRed.opacity(0.15))
    }

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("メッセージを入力...", text: $inputText, axis: .vertical)
                .focused($isInputFocused)
                .textFieldStyle(.plain)
                .padding(12)
                .lineLimit(1...5)
                .background(AppTheme.surface)
                .foregroundStyle(AppTheme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(AppTheme.surfaceElevated, lineWidth: 1)
                )

            Button {
                isInputFocused = false
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(canSend ? AppTheme.accent : AppTheme.textSecondary.opacity(0.5))
            }
            .disabled(!canSend)
        }
        .padding()
        .background(AppTheme.background)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(AppTheme.surfaceElevated),
            alignment: .top
        )
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
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

    private func updateRoomName(_ name: String) {
        guard let token = appState.authToken else { return }
        guard let url = URL(string: APIClient.baseURL + "/chat/rooms/\(roomId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.allHTTPHeaderFields = APIClient.authHeader(token)
        req.httpBody = try? JSONEncoder().encode(["name": name])
        Task {
            _ = try? await URLSession.shared.data(for: req)
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
                    messages = messages + [m]
                }
            case "error":
                if let e = try? JSONDecoder().decode(ProviderError.self, from: data) {
                    errorMessage = "\(e.provider): \(e.error)"
                }
            case "done":
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
        HStack(alignment: .top, spacing: 10) {
            if message.role == "user" {
                Spacer(minLength: 60)
            } else {
                providerBadge
            }

            Text(message.content)
                .font(AppTheme.bodyFont)
                .foregroundStyle(message.role == "user" ? .white : AppTheme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(message.role == "user" ? AppTheme.userBubble : AppTheme.aiBubble)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(message.role == "user" ? Color.clear : AppTheme.surfaceElevated.opacity(0.5), lineWidth: 1)
                )

            if message.role == "user" {
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 60)
            }
        }
        .animation(.easeOut(duration: 0.2), value: message.id)
    }

    @ViewBuilder
    private var providerBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: providerIcon)
                .font(.caption2)
            Text(providerLabel)
                .font(AppTheme.captionFont)
        }
        .foregroundStyle(AppTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppTheme.surface)
        .clipShape(Capsule())
    }

    private var providerLabel: String {
        switch message.provider {
        case "openai": return "ChatGPT"
        case "gemini": return "Gemini"
        default: return ""
        }
    }

    private var providerIcon: String {
        switch message.provider {
        case "openai": return "sparkles"
        case "gemini": return "bolt.fill"
        default: return "bubble.left.fill"
        }
    }
}

struct MessagesResponse: Codable {
    let messages: [Message]
}

struct ErrorBody: Codable {
    let error: String?
}

struct EditRoomNameSheet: View {
    @State private var name: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    init(currentName: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _name = State(initialValue: currentName)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("ルーム名", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("ルーム名を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }
}
