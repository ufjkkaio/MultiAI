import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isAgreed: Bool { didSet { UserDefaults.standard.set(isAgreed, forKey: "isAgreed") } }
    @Published var authToken: String? { didSet { UserDefaults.standard.set(authToken, forKey: "authToken") } }
    @Published var userId: String? { didSet { UserDefaults.standard.set(userId, forKey: "userId") } }
    @Published var isSubscribed: Bool = false
    
    var isLoggedIn: Bool { authToken != nil }
    
    init() {
        self.isAgreed = UserDefaults.standard.bool(forKey: "isAgreed")
        self.authToken = UserDefaults.standard.string(forKey: "authToken")
        self.userId = UserDefaults.standard.string(forKey: "userId")
    }
    
    func logout() {
        authToken = nil
        userId = nil
        isSubscribed = false
    }
}
