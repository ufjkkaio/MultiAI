import SwiftUI

struct ChatRoomListView: View {
    @EnvironmentObject var appState: AppState
    @State private var rooms: [Room] = []
    
    var body: some View {
        Group {
            if rooms.isEmpty {
                VStack(spacing: 16) {
                    Text("ルームがありません")
                        .foregroundStyle(.secondary)
                    Button("最初のルームを作成") {
                        createRoom()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rooms) { room in
                    NavigationLink(value: room) {
                        Text("ルーム \(room.id.prefix(8))...")
                    }
                }
                .navigationDestination(for: Room.self) { room in
                    ChatView(roomId: room.id)
                }
            }
        }
        .onAppear { loadRooms() }
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
    
    private func createRoom() {
        guard let token = appState.authToken else { return }
        guard let url = URL(string: APIClient.baseURL + "/chat/rooms") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.allHTTPHeaderFields = APIClient.authHeader(token)
        
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

struct RoomsResponse: Codable {
    let rooms: [Room]
}

