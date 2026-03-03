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

struct ImageAttachment: Codable {
    let base64: String
    let mediaType: String
    enum CodingKeys: String, CodingKey {
        case base64
        case mediaType = "media_type"
    }
}

struct Message: Codable, Identifiable {
    let id: String
    let role: String
    let provider: String?
    let content: String
    let expandedFromId: String?
    let attachmentBase64: String?
    let attachmentMediaType: String?
    let attachments: [ImageAttachment]?
    let createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, role, provider, content, createdAt
        case expandedFromId = "expanded_from_id"
        case attachmentBase64 = "attachment_base64"
        case attachmentMediaType = "attachment_media_type"
        case attachments
    }
    var effectiveAttachments: [ImageAttachment] {
        if let a = attachments, !a.isEmpty { return a }
        if let b = attachmentBase64, let m = attachmentMediaType {
            return [ImageAttachment(base64: b, mediaType: m)]
        }
        return []
    }
}

struct SendMessageResponse: Codable {
    let userMessage: UserMessagePart
    let assistantMessages: [Message]
    let errors: [ProviderError]?
}

struct UserMessagePart: Codable {
    let content: String
}

struct UserMessageSSE: Codable {
    let id: String?
    let content: String
    let attachmentBase64: String?
    let attachmentMediaType: String?
    let attachments: [ImageAttachment]?
    let createdAt: String?
    enum CodingKeys: String, CodingKey {
        case id, content, createdAt
        case attachmentBase64 = "attachment_base64"
        case attachmentMediaType = "attachment_media_type"
        case attachments
    }
    var effectiveAttachments: [ImageAttachment] {
        if let a = attachments, !a.isEmpty { return a }
        if let b = attachmentBase64, let m = attachmentMediaType {
            return [ImageAttachment(base64: b, mediaType: m)]
        }
        return []
    }
}

struct ProviderError: Codable {
    let provider: String
    let error: String
}

struct ChunkEvent: Codable {
    let provider: String
    let delta: String
}
