import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private struct PickableImage: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickableImage(data: data)
        }
    }
}

struct ChatView: View {
    let roomId: String
    var roomName: String?
    var onRoomUpdated: (() -> Void)?

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var displayName: String
    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool
    @State private var showEditNameSheet = false
    @State private var showCopiedFeedback = false
    @State private var scrollTrigger = UUID()
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImageDatas: [Data] = []
    @State private var showAttachmentSubscriptionAlert = false
    @State private var didRefreshFreeRemainingForThisSend = false

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
            aiDisclaimer
            inputArea
        }
        .background(AppTheme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 4) {
                    Text(displayName)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Button {
                        showEditNameSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .toolbarBackground(AppTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.light)
        .overlay {
            if showCopiedFeedback {
                VStack {
                    Text("コピーしました")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.95))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppTheme.surface.opacity(0.95))
                        .clipShape(Capsule())
                        .padding(.top, 56)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .animation(.easeInOut(duration: 0.2), value: showCopiedFeedback)
            }
        }
        .onAppear { loadMessages() }
        .sheet(isPresented: $showEditNameSheet) {
            EditRoomNameSheet(
                currentName: displayName,
                onSave: { newName in
                    displayName = newName.isEmpty ? String(roomId.prefix(8)) + "..." : newName
                    showEditNameSheet = false
                    Task {
                        await updateRoomName(newName)
                        onRoomUpdated?()
                    }
                },
                onCancel: { showEditNameSheet = false }
            )
        }
        .alert("サブスクリプションが必要です", isPresented: $showAttachmentSubscriptionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("写真・ファイルの添付はサブスクリプション登録後にご利用いただけます。")
        }
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { msg in
                        MessageRow(
                            message: msg,
                            onCopy: {
                                showCopiedFeedback = true
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(1.5))
                                    showCopiedFeedback = false
                                }
                            }
                        )
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
                scrollToLast(proxy: proxy)
            }
            .onChange(of: scrollTrigger) { _, _ in
                scrollToLast(proxy: proxy)
            }
        }
    }

    private func scrollToLast(proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(last.id, anchor: .bottom)
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
        VStack(alignment: .leading, spacing: 8) {
            if !selectedImageDatas.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImageDatas.enumerated()), id: \.offset) { index, data in
                            if let uiImage = UIImage(data: data) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    Button {
                                        removeSelectedImage(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.body)
                                            .foregroundStyle(.white)
                                            .shadow(radius: 1)
                                    }
                                    .padding(4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 80)
            }
            HStack(alignment: .bottom, spacing: 10) {
                if appState.isSubscribed {
                    PhotosPicker(
                        selection: $selectedPhotoItems,
                        maxSelectionCount: 5,
                        matching: .images
                    ) {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(width: 36, height: 36)
                    }
                    .onChange(of: selectedPhotoItems) { _, newItems in
                        Task {
                            var datas: [Data] = []
                            for item in newItems {
                                if let d = try? await item.loadTransferable(type: PickableImage.self)?.data {
                                    datas.append(d)
                                }
                            }
                            await MainActor.run { selectedImageDatas = datas }
                        }
                    }
                } else {
                    Button {
                        showAttachmentSubscriptionAlert = true
                    } label: {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(AppTheme.textPrimary)
                            .frame(width: 36, height: 36)
                    }
                }
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
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(AppTheme.background)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(AppTheme.surfaceElevated),
            alignment: .top
        )
    }

    private var aiDisclaimer: some View {
        Text("※AIは間違えることがあります")
            .font(AppTheme.captionFont)
            .foregroundStyle(AppTheme.textSecondary.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func removeSelectedImage(at index: Int) {
        guard index < selectedImageDatas.count else { return }
        selectedImageDatas.remove(at: index)
        if index < selectedPhotoItems.count {
            selectedPhotoItems.remove(at: index)
        }
    }

    private func loadMessages() {
        guard let token = appState.authToken else { return }
        guard let url = URL(string: APIClient.baseURL + "/chat/rooms/\(roomId)/messages") else { return }
        var req = URLRequest(url: url)
        req.allHTTPHeaderFields = APIClient.authHeader(token)

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let dec = JSONDecoder()
                dec.keyDecodingStrategy = .convertFromSnakeCase
                let res = try dec.decode(MessagesResponse.self, from: data)
                await MainActor.run {
                    messages = res.messages
                    errorMessage = nil
                }
            } catch {
                await MainActor.run { errorMessage = "履歴の読み込みに失敗しました" }
            }
        }
    }

    private func updateRoomName(_ name: String) async {
        guard let token = appState.authToken else { return }
        guard let url = URL(string: APIClient.baseURL + "/chat/rooms/\(roomId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.allHTTPHeaderFields = APIClient.authHeader(token)
        req.httpBody = try? JSONEncoder().encode(["name": name])
        _ = try? await URLSession.shared.data(for: req)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let token = appState.authToken else { return }

        struct AttachmentPayload: Encodable {
            let image_base64: String
            let image_media_type: String
        }
        var attachmentsPayload: [AttachmentPayload] = []
        for data in selectedImageDatas {
            guard let uiImage = UIImage(data: data) else { continue }
            let maxSide: CGFloat = 384
            let scale = min(maxSide / max(uiImage.size.width, uiImage.size.height), 1)
            let size = CGSize(width: uiImage.size.width * scale, height: uiImage.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(size, true, 1)
            uiImage.draw(in: CGRect(origin: .zero, size: size))
            let resized = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            if let jpeg = (resized ?? uiImage).jpegData(compressionQuality: 0.4) {
                attachmentsPayload.append(AttachmentPayload(image_base64: jpeg.base64EncodedString(), image_media_type: "image/jpeg"))
            }
        }

        struct SendBody: Encodable {
            let content: String
            let attachments: [AttachmentPayload]?
        }
        guard let url = URL(string: APIClient.baseURL + "/chat/rooms/\(roomId)/messages") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.allHTTPHeaderFields = APIClient.authHeader(token)
        req.httpBody = try? JSONEncoder().encode(SendBody(
            content: text,
            attachments: attachmentsPayload.isEmpty ? nil : attachmentsPayload
        ))

        isSending = true
        didRefreshFreeRemainingForThisSend = false
        inputText = ""
        selectedPhotoItems = []
        selectedImageDatas = []
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
                        if err?.code == "ATTACHMENT_REQUIRED_SUBSCRIPTION" {
                            errorMessage = "写真・ファイル添付は課金後にご利用ください"
                        } else if err?.code == "SUBSCRIPTION_REQUIRED" {
                            errorMessage = "サブスクリプションが必要です"
                        } else {
                            errorMessage = err?.error ?? "サブスクリプションが必要です"
                        }
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
                        messages.append(Message(id: UUID().uuidString, role: "user", provider: nil, content: res.userMessage.content, expandedFromId: nil, attachmentBase64: nil, attachmentMediaType: nil, attachments: nil, createdAt: nil))
                        messages.append(contentsOf: res.assistantMessages)
                        isSending = false
                    }
                    if subscriptionManager.freeRemaining != nil && !didRefreshFreeRemainingForThisSend {
                        didRefreshFreeRemainingForThisSend = true
                        if let remaining = subscriptionManager.freeRemaining, remaining > 0 {
                            subscriptionManager.freeRemaining = remaining - 1
                        }
                        Task { await subscriptionManager.refreshSubscriptionStatus() }
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
                let dec = JSONDecoder()
                dec.keyDecodingStrategy = .convertFromSnakeCase
                if let u = try? dec.decode(UserMessageSSE.self, from: data) {
                    let newMsg = Message(
                        id: u.id ?? UUID().uuidString,
                        role: "user",
                        provider: nil,
                        content: u.content,
                        expandedFromId: nil,
                        attachmentBase64: u.attachmentBase64,
                        attachmentMediaType: u.attachmentMediaType,
                        attachments: u.effectiveAttachments.isEmpty ? nil : u.effectiveAttachments,
                        createdAt: u.createdAt
                    )
                    messages = messages + [newMsg]
                }
            case "chunk":
                if let c = try? JSONDecoder().decode(ChunkEvent.self, from: data), !c.delta.isEmpty {
                    let streamId = "streaming-\(c.provider)"
                    if let idx = messages.firstIndex(where: { $0.id == streamId }) {
                        let cur = messages[idx]
                        let updated = Message(id: streamId, role: "assistant", provider: c.provider, content: cur.content + c.delta, expandedFromId: nil, attachmentBase64: nil, attachmentMediaType: nil, attachments: nil, createdAt: nil)
                        messages = messages.enumerated().map { $0.offset == idx ? updated : $0.element }
                    } else {
                        let newMsg = Message(id: streamId, role: "assistant", provider: c.provider, content: c.delta, expandedFromId: nil, attachmentBase64: nil, attachmentMediaType: nil, attachments: nil, createdAt: nil)
                        messages = messages + [newMsg]
                    }
                    scrollTrigger = UUID()
                }
            case "message":
                let dec = JSONDecoder()
                dec.keyDecodingStrategy = .convertFromSnakeCase
                if let m = try? dec.decode(Message.self, from: data) {
                    let streamId = "streaming-\(m.provider ?? "")"
                    messages = messages.filter { $0.id != streamId } + [m]
                }
            case "error":
                if let e = try? JSONDecoder().decode(ProviderError.self, from: data) {
                    errorMessage = "\(e.provider): \(e.error)"
                }
                loadMessages() // 保存済みメッセージを表示するため再取得
            case "done":
                loadMessages()
                if subscriptionManager.freeRemaining != nil && !didRefreshFreeRemainingForThisSend {
                    didRefreshFreeRemainingForThisSend = true
                    if let remaining = subscriptionManager.freeRemaining, remaining > 0 {
                        subscriptionManager.freeRemaining = remaining - 1
                    }
                    Task { await subscriptionManager.refreshSubscriptionStatus() }
                }
            default:
                break
            }
        }
    }
}

struct MessageRow: View {
    let message: Message
    var onCopy: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if message.role == "user" {
                Spacer(minLength: 60)
            } else {
                copyButton
                providerBadge
            }

            messageBubble

            if message.role == "user" {
                copyButton
            } else {
                Spacer(minLength: 60)
            }
        }
        .animation(.easeOut(duration: 0.2), value: message.id)
    }

    private func copyContent() {
        let text = message.content.isEmpty ? "(添付のみ)" : message.content
        UIPasteboard.general.string = text
        onCopy?()
    }

    private var copyButton: some View {
        Button {
            copyContent()
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var messageBubble: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 8) {
            ForEach(Array(message.effectiveAttachments.enumerated()), id: \.offset) { _, att in
                if let data = Data(base64Encoded: att.base64), let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            if !message.content.isEmpty {
                Text(message.content)
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(message.role == "user" ? .white : AppTheme.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(message.role == "user" ? AppTheme.userBubble : AppTheme.aiBubble)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(message.role == "user" ? Color.clear : AppTheme.surfaceElevated.opacity(0.5), lineWidth: 1)
        )
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
