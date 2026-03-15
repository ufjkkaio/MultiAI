import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showSideMenu = false
    @State private var showPaywall = false
    @State private var chatPath: [Room] = []
    @State private var showSearchSheet = false
    @State private var roomForFullScreen: Room?

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        NavigationStack(path: $chatPath) {
            ZStack {
                ChatRoomListView(path: $chatPath, showSearchSheet: $showSearchSheet, roomForFullScreen: $roomForFullScreen, isPad: isPad)
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
                            HStack(spacing: 12) {
                                Button {
                                    showSearchSheet = true
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .font(.title3)
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
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
                    }
                    .toolbarBackground(AppTheme.background, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
            }
            .background(AppTheme.background)
            .preferredColorScheme(.light)
        }
        .fullScreenCover(item: $roomForFullScreen) { room in
            NavigationStack {
                ChatView(roomId: room.id, roomName: room.name, onRoomUpdated: { })
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("閉じる") { roomForFullScreen = nil }
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                    }
            }
            .environmentObject(appState)
            .environmentObject(subscriptionManager)
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
