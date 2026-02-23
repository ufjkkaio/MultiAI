import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Group {
            if !appState.isAgreed {
                AgreementView()
            } else if !appState.isLoggedIn {
                AuthView()
            } else {
                MainTabView()
            }
        }
    }
}
