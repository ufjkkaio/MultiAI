import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if !appState.isAgreed {
                AgreementView()
            } else if appState.authToken == nil {
                if appState.guestBootstrapError != nil {
                    // ゲストセッションの発行に失敗した場合のみ、手動ログインを許可する
                    AuthView()
                } else {
                    ProgressView()
                }
            } else {
                MainTabView()
            }
        }
        .task(id: appState.isAgreed) {
            if appState.isAgreed {
                await appState.bootstrapGuestIfNeeded()
            }
        }
        .onChange(of: appState.authToken) { _, token in
            // logout などで authToken が nil になった場合に、ゲスト再生成を確実に走らせる
            guard appState.isAgreed, token == nil else { return }
            Task { await appState.bootstrapGuestIfNeeded() }
        }
    }
}
