import Foundation

enum APIClient {
    static var baseURL: String {
        ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "http://localhost:3000"
    }
    
    static func authHeader(_ token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)"]
    }
}

struct Room: Codable, Identifiable, Hashable {
    let id: String
    let createdAt: String?
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Room, r: Room) -> Bool { l.id == r.id }
}

struct Message: Codable, Identifiable {
    let id: String
    let role: String
    let provider: String?
    let content: String
    let createdAt: String?
}

struct SendMessageResponse: Codable {
    let userMessage: UserMessagePart
    let assistantMessages: [Message]
    let errors: [ProviderError]?
}

struct UserMessagePart: Codable {
    let content: String
}

struct ProviderError: Codable {
    let provider: String
    let error: String
}
