import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    var body: some View {
        NavigationStack {
            ChatRoomListView()
                .navigationTitle("チャット")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if appState.isSubscribed {
                                Text("有料プラン利用中")
                            } else {
                                Text("サブスクを購入して利用")
                            }
                            Button("ログアウト", role: .destructive) {
                                appState.logout()
                            }
                        } label: {
                            Image(systemName: "person.circle")
                        }
                    }
                }
        }
        .onAppear {
            Task { await subscriptionManager.syncWithBackend() }
        }
    }
}
