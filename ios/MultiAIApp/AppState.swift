import Foundation
import Combine
import Security

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

    private var guestIdService: String {
        (Bundle.main.bundleIdentifier ?? "com.multiai.app") + ".guestId"
    }
    
    private let guestIdAccount = "guest_id"
    
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
        
        guard let guestId = loadOrCreateGuestId() else {
            guestBootstrapError = "ゲストIDの作成に失敗しました"
            return
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // guestBootstrap がハングして ProgressView が終わらない事態を避ける
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["guestId": guestId])
        
        do {
            struct GuestBootstrapTimeoutError: Error {}
            let (data, _) = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
                group.addTask { try await URLSession.shared.data(for: req) }
                group.addTask {
                    try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                    throw GuestBootstrapTimeoutError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
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

    private func loadOrCreateGuestId() -> String? {
        if let existing = loadGuestIdFromKeychain() { return existing }
        let newId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        saveGuestIdToKeychain(newId)
        return newId
    }

    private func loadGuestIdFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: guestIdService,
            kSecAttrAccount as String: guestIdAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var data: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &data)
        guard status == errSecSuccess, let d = data as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func saveGuestIdToKeychain(_ id: String) {
        let idData = id.data(using: .utf8) ?? Data()
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: guestIdService,
            kSecAttrAccount as String: guestIdAccount
        ]
        let attributes: [String: Any] = [ kSecValueData as String: idData ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        let addQuery = baseQuery.merging(attributes) { _, new in new }
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}
