import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showSideMenu = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ZStack {
                ChatRoomListView()
                    .navigationTitle("チャット")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showSideMenu = true
                            } label: {
                                Image(systemName: "line.3.horizontal")
                                    .font(.title3)
                                    .foregroundStyle(AppTheme.textPrimary)
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            if !appState.isSubscribed {
                                Button {
                                    showPaywall = true
                                } label: {
                                    Image(systemName: "crown.fill")
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                        }
                    }
                    .toolbarBackground(AppTheme.background, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }
            .background(AppTheme.background)
            .preferredColorScheme(.light)
        }
        .sheet(isPresented: $showSideMenu) {
            SideMenuView(onSubscriptionTap: {
                showPaywall = true
            })
            .environmentObject(appState)
            .environmentObject(subscriptionManager)
        }
        .sheet(isPresented: $showPaywall) {
            SubscriptionPaywallView()
                .environmentObject(subscriptionManager)
        }
        .onAppear {
            Task { await subscriptionManager.refreshSubscriptionStatus() }
        }
    }
}
