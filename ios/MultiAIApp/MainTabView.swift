import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showSideMenu = false
    @State private var showPaywall = false

    private var openMenuSwipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let fromLeft = value.startLocation.x < 40
                let swipedRight = value.translation.width > 40
                if fromLeft && swipedRight {
                    showSideMenu = true
                }
            }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
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

                Color.clear
                    .frame(width: 44)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(openMenuSwipe)
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
