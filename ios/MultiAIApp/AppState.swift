import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isAgreed: Bool { didSet { UserDefaults.standard.set(isAgreed, forKey: "isAgreed") } }
    @Published var authToken: String? { didSet { UserDefaults.standard.set(authToken, forKey: "authToken") } }
    @Published var userId: String? { didSet { UserDefaults.standard.set(userId, forKey: "userId") } }
    @Published var isSubscribed: Bool = false
    
    var isLoggedIn: Bool { authToken != nil }
    
    private static func cachedSubscriptionKey(userId: String?) -> String {
        "cachedIsSubscribed_\(userId ?? "none")"
    }
    
    init() {
        self.isAgreed = UserDefaults.standard.bool(forKey: "isAgreed")
        self.authToken = UserDefaults.standard.string(forKey: "authToken")
        self.userId = UserDefaults.standard.string(forKey: "userId")
        let cacheKey = Self.cachedSubscriptionKey(userId: userId)
        self.isSubscribed = UserDefaults.standard.bool(forKey: cacheKey)
    }
    
    func logout() {
        authToken = nil
        userId = nil
        isSubscribed = false
    }
}
