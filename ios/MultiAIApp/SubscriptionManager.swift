import Foundation
import Combine
import StoreKit

/// サブスクリプション状態を取得し、バックエンドと同期する。
/// 本番では StoreKit 2 で購入・復元し、ここで currentEntitlements を確認して isActive を決める。
@MainActor
final class SubscriptionManager: ObservableObject {
    @Published var isActive: Bool = false
    
    private let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
    }
    
    func syncWithBackend() async {
        guard let token = appState.authToken else { return }
        guard let url = URL(string: APIClient.baseURL + "/subscription/status") else { return }
        var req = URLRequest(url: url)
        req.allHTTPHeaderFields = APIClient.authHeader(token)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let res = try JSONDecoder().decode(SubscriptionStatusResponse.self, from: data)
            await MainActor.run {
                appState.isSubscribed = res.isActive
                isActive = res.isActive
            }
        } catch {}
    }
    
    /// 購入・復元後にアプリから呼ぶ。本番では StoreKit のトランザクション検証後に true を送る。
    func setSubscriptionActive(_ active: Bool) async {
        guard let token = appState.authToken else { return }
        guard let url = URL(string: APIClient.baseURL + "/subscription/status") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.allHTTPHeaderFields = APIClient.authHeader(token)
        req.httpBody = try? JSONEncoder().encode(["isActive": active])
        
        _ = try? await URLSession.shared.data(for: req)
        await MainActor.run {
            appState.isSubscribed = active
            isActive = active
        }
    }
}

struct SubscriptionStatusResponse: Codable {
    let isActive: Bool
}
