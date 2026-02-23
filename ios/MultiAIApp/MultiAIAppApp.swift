import SwiftUI

@main
struct MultiAIAppApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var subscriptionManager: SubscriptionManager
    
    init() {
        let state = AppState()
        _appState = StateObject(wrappedValue: state)
        _subscriptionManager = StateObject(wrappedValue: SubscriptionManager(appState: state))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(subscriptionManager)
        }
    }
}
