import SwiftUI

struct ChatRoomListView: View {
    @EnvironmentObject var appState: AppState
    @State private var rooms: [Room] = []
    @State private var showCreateSheet = false

    var body: some View {
        Group {
            if rooms.isEmpty {
                emptyState
            } else {
                roomList
            }
        }
        .background(AppTheme.background)
        .scrollContentBackground(.hidden)
        .onAppear { loadRooms() }
        .sheet(isPresented: $showCreateSheet) {
            CreateRoomSheet(
                onCreate: { name in
                    showCreateSheet = false
                    createRoom(name: name)
                },
                onCancel: { showCreateSheet = false }
            )
        }
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
                                Text(formatDate(created))
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

    private func loadRooms() {
        guard let token = appState.authToken else { return }
        guard let url = URL(string: APIClient.baseURL + "/chat/rooms") else { return }
        var req = URLRequest(url: url)
        req.allHTTPHeaderFields = APIClient.authHeader(token)

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                let res = try JSONDecoder().decode(RoomsResponse.self, from: data)
                await MainActor.run {
                    rooms = res.rooms
                }
            } catch {
                await MainActor.run { rooms = [] }
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
