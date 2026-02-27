import Foundation

enum APIClient {
    static var baseURL: String {
        ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://multiai-production-ac5b.up.railway.app"
    }
    
    static func authHeader(_ token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)"]
    }
}

struct Room: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
    }
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
