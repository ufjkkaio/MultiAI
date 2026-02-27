import Foundation
import Combine
import StoreKit

private let subscriptionProductId = "multiAI.MultiAI.monthly"

/// サブスクリプション状態を取得し、バックエンドと同期する。
@MainActor
final class SubscriptionManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    private func updateFromStoreKit() async {
        var hasEntitlement = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == subscriptionProductId {
                hasEntitlement = true
                break
            }
        }
        if hasEntitlement {
            await setSubscriptionActive(true)
        }
    }

    func refreshSubscriptionStatus() async {
        await updateFromStoreKit()
        await syncWithBackend()
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

    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let list = try await Product.products(for: [subscriptionProductId])
            products = list.sorted { $0.price < $1.price }
            if products.isEmpty {
                errorMessage = "商品を取得できませんでした"
            }
        } catch {
            errorMessage = "商品の読み込みに失敗しました"
        }
    }

    func purchase() async {
        guard let product = products.first else {
            await loadProducts()
            guard let p = products.first else { return }
            await performPurchase(p)
            return
        }
        await performPurchase(product)
    }

    private func performPurchase(_ product: Product) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    await setSubscriptionActive(true)
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "購入が保留中です"
            @unknown default:
                break
            }
        } catch {
            errorMessage = "購入に失敗しました"
        }
    }

    func restore() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await updateFromStoreKit()
            if !isActive {
                errorMessage = "復元できる購入がありません"
            }
        } catch {
            errorMessage = "復元に失敗しました"
        }
    }

    /// 購入・復元後にアプリから呼ぶ。
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
