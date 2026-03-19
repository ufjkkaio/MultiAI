import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isAgreed: Bool { didSet { UserDefaults.standard.set(isAgreed, forKey: "isAgreed") } }
    @Published var authToken: String? { didSet { UserDefaults.standard.set(authToken, forKey: "authToken") } }
    @Published var userId: String? { didSet { UserDefaults.standard.set(userId, forKey: "userId") } }
    @Published var isSubscribed: Bool = false
    @Published var isGuestMode: Bool { didSet { UserDefaults.standard.set(isGuestMode, forKey: "isGuestMode") } }
    @Published var isBootstrappingGuest: Bool = false
    @Published var guestBootstrapError: String? = nil
    
    var isLoggedIn: Bool { authToken != nil }
    
    private static func cachedSubscriptionKey(userId: String?) -> String {
        "cachedIsSubscribed_\(userId ?? "none")"
    }
    
    init() {
        self.isAgreed = UserDefaults.standard.bool(forKey: "isAgreed")
        self.authToken = UserDefaults.standard.string(forKey: "authToken")
        self.userId = UserDefaults.standard.string(forKey: "userId")
        self.isGuestMode = UserDefaults.standard.bool(forKey: "isGuestMode")
        let cacheKey = Self.cachedSubscriptionKey(userId: userId)
        self.isSubscribed = UserDefaults.standard.bool(forKey: cacheKey)
    }
    
    /// 起動時にログイン画面を出さず、ゲストとして利用できるようにトークンを発行します。
    /// 失敗した場合のみ `guestBootstrapError` を設定します。
    func bootstrapGuestIfNeeded() async {
        guard isAgreed else { return }
        guard authToken == nil else { return }
        guard !isBootstrappingGuest else { return }
        
        isBootstrappingGuest = true
        guestBootstrapError = nil
        defer { isBootstrappingGuest = false }
        
        guard let url = URL(string: APIClient.baseURL + "/auth/guest") else {
            guestBootstrapError = "ゲストセッションの発行に失敗しました"
            return
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let res = try JSONDecoder().decode(AuthResponse.self, from: data)
            authToken = res.token
            userId = res.userId
            isGuestMode = true
        } catch {
            guestBootstrapError = "ゲストセッションの発行に失敗しました"
        }
    }
    
    func logout() {
        authToken = nil
        userId = nil
        isSubscribed = false
        isGuestMode = false
        guestBootstrapError = nil
    }
}
