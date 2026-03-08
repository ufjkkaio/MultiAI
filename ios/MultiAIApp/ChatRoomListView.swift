import SwiftUI

struct ChatRoomListView: View {
    @Binding var path: [Room]
    @Binding var showSearchSheet: Bool
    @EnvironmentObject var appState: AppState
    @State private var rooms: [Room] = []
    @State private var showCreateSheet = false
    @State private var isLoading = true
    @State private var roomToDelete: Room?

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if rooms.isEmpty {
                emptyState
            } else {
                roomList
            }
        }
        .background(AppTheme.background)
        .scrollContentBackground(.hidden)
        .onAppear { loadRooms() }
        .sheet(isPresented: $showSearchSheet) {
            MessageSearchSheet(
                onSelectRoom: { room in
                    showSearchSheet = false
                    path.append(room)
                },
                onDismiss: { showSearchSheet = false }
            )
            .environmentObject(appState)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateRoomSheet(
                onCreate: { name in
                    showCreateSheet = false
                    createRoom(name: name)
                },
                onCancel: { showCreateSheet = false }
            )
        }
        .alert("ルームを削除", isPresented: Binding(
            get: { roomToDelete != nil },
            set: { if !$0 { roomToDelete = nil } }
        )) {
            Button("キャンセル", role: .cancel) { roomToDelete = nil }
            Button("削除", role: .destructive) {
                if let room = roomToDelete {
                    deleteRoom(room)
                    roomToDelete = nil
                }
            }
        } message: {
            Text("このルームと会話履歴は削除され、復元できません。よろしいですか？")
        }
    }

    private var loadingView: some View {
        ProgressView()
            .scaleEffect(1.4)
            .tint(AppTheme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.6))

            Text("チャットルームがありません")
                .font(AppTheme.headlineFont)
                .foregroundStyle(AppTheme.textSecondary)

            Text("最初のルームを作成して、\nChatGPT と Gemini に同時に質問してみましょう")
                .font(AppTheme.bodyFont)
                .foregroundStyle(AppTheme.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var roomList: some View {
        List {
            ForEach(rooms) { room in
                NavigationLink(value: room) {
                    HStack(spacing: 14) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(roomDisplayName(room))
                                .font(AppTheme.headlineFont)
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(1)

                            if let created = room.createdAt {
                                Text("作成日： \(formatDate(created))")
                                    .font(AppTheme.captionFont)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(AppTheme.surface)
                .listRowSeparatorTint(AppTheme.surfaceElevated)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        roomToDelete = room
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2)
                    .fontWeight(.medium)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accent)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .padding()
            .background(AppTheme.background)
        }
        .navigationDestination(for: Room.self) { room in
            ChatView(roomId: room.id, roomName: room.name, onRoomUpdated: { loadRooms() })
        }
    }

    private func roomDisplayName(_ room: Room) -> String {
        if let name = room.name, !name.isEmpty {
            return name
        }
        return String(room.id.prefix(8)) + "..."
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let d = date else { return iso }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: d)
    }

    private func deleteRoom(_ room: Room) {
        guard let token = appState.authToken else { return }
        guard let url = URL(string: APIClient.baseURL + "/chat/rooms/\(room.id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.allHTTPHeaderFields = APIClient.authHeader(token)
        Task {
            _ = try? await URLSession.shared.data(for: req)
            await MainActor.run { loadRooms() }
        }
    }

    private func loadRooms() {
        guard let token = appState.authToken else { return }
        guard let url = URL(string: APIClient.baseURL + "/chat/rooms") else { return }
        var req = URLRequest(url: url)
        req.allHTTPHeaderFields = APIClient.authHeader(token)

        isLoading = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let res = try JSONDecoder().decode(RoomsResponse.self, from: data)
                await MainActor.run {
                    rooms = res.rooms
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    rooms = []
                    isLoading = false
                }
            }
        }
    }

    private func createRoom(name: String = "") {
        guard let token = appState.authToken else { return }
        guard let url = URL(string: APIClient.baseURL + "/chat/rooms") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.allHTTPHeaderFields = APIClient.authHeader(token)
        req.httpBody = try? JSONEncoder().encode(["name": name])

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let room = try JSONDecoder().decode(Room.self, from: data)
                await MainActor.run {
                    rooms.insert(room, at: 0)
                }
            } catch {}
        }
    }
}

struct CreateRoomSheet: View {
    @State private var roomName = ""
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                TextField("ルーム名", text: $roomName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("新しいルーム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                        .foregroundStyle(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") {
                        onCreate(roomName.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.accent)
                }
            }
        }
    }
}

struct RoomsResponse: Codable {
    let rooms: [Room]
}

struct MessageSearchSheet: View {
    @EnvironmentObject var appState: AppState
    @State private var query = ""
    @State private var results: [MessageSearchResult] = []
    @State private var isSearching = false
    let onSelectRoom: (Room) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.textSecondary)
                    TextField("メッセージを検索", text: $query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onSubmit { runSearch() }
                }
                .padding(12)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)

                if isSearching {
                    ProgressView()
                        .padding(.top, 24)
                } else if results.isEmpty && !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("該当するメッセージがありません")
                        .font(AppTheme.bodyFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .padding(.top, 24)
                } else {
                    List {
                        ForEach(results) { r in
                            Button {
                                let room = Room(id: r.roomId, name: r.roomName, createdAt: r.createdAt)
                                onSelectRoom(room)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(roomDisplayName(r.roomName, id: r.roomId))
                                            .font(AppTheme.captionFont)
                                            .foregroundStyle(AppTheme.accent)
                                        Spacer()
                                        if let created = r.createdAt {
                                            Text(formatDate(created))
                                                .font(AppTheme.captionFont)
                                                .foregroundStyle(AppTheme.textSecondary)
                                        }
                                    }
                                    highlightedText(content: r.content, query: query, baseColor: AppTheme.textPrimary, highlightColor: AppTheme.accent)
                                        .font(AppTheme.bodyFont)
                                        .lineLimit(3)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(AppTheme.surface)
                        }
                    }
                    .listStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 16)
            .background(AppTheme.background)
            .navigationTitle("メッセージ検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { onDismiss() }
                        .foregroundStyle(AppTheme.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("検索") { runSearch() }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .onAppear {
                if !query.isEmpty { runSearch() }
            }
        }
    }

    /// 検索語に色をつけて目立たせる（大文字小文字区別なし）。iOS 26 の Text + 非推奨を避けて AttributedString を使用。
    private func highlightedText(content: String, query: String, baseColor: Color, highlightColor: Color) -> Text {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Text(content) }
        var segments: [(String, Bool)] = []
        var remaining = content
        while let range = remaining.range(of: q, options: .caseInsensitive) {
            let before = String(remaining[..<range.lowerBound])
            let match = String(remaining[range])
            if !before.isEmpty { segments.append((before, false)) }
            if !match.isEmpty { segments.append((match, true)) }
            remaining = String(remaining[range.upperBound...])
        }
        if !remaining.isEmpty { segments.append((remaining, false)) }
        guard !segments.isEmpty else { return Text(content) }
        var result = AttributedString()
        for (str, isMatch) in segments {
            var segment = AttributedString(str)
            if isMatch {
                segment.foregroundColor = highlightColor
                segment.backgroundColor = highlightColor.opacity(0.35)
                segment.font = .body.weight(.bold)
            }
            result.append(segment)
        }
        return Text(result)
    }

    private func roomDisplayName(_ name: String, id: String) -> String {
        if !name.isEmpty { return name }
        return String(id.prefix(8)) + "..."
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let d = date else { return iso }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "ja_JP")
        return f.string(from: d)
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let token = appState.authToken else {
            results = []
            return
        }
        guard let url = URL(string: APIClient.baseURL + "/chat/search?q=" + q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!) else { return }
        var req = URLRequest(url: url)
        req.allHTTPHeaderFields = APIClient.authHeader(token)
        isSearching = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let res = try JSONDecoder().decode(MessageSearchResponse.self, from: data)
                await MainActor.run {
                    results = res.results
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    results = []
                    isSearching = false
                }
            }
        }
    }
}
