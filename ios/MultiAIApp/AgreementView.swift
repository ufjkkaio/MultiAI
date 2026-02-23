import SwiftUI

struct AgreementView: View {
    @EnvironmentObject var appState: AppState
    @State private var agreed = false
    
    var termsURL: URL? { URL(string: "https://example.com/terms") }
    var privacyURL: URL? { URL(string: "https://example.com/privacy") }
    
    var body: some View {
        VStack(spacing: 24) {
            Text("利用規約とプライバシーポリシー")
                .font(.headline)
            
            if let terms = termsURL {
                Link("利用規約", destination: terms)
            }
            if let privacy = privacyURL {
                Link("プライバシーポリシー", destination: privacy)
            }
            
            HStack(alignment: .top, spacing: 8) {
                Toggle("", isOn: $agreed)
                    .labelsHidden()
                Text("利用規約とプライバシーポリシーに同意する")
                    .font(.body)
            }
            .padding(.horizontal)
            
            Button("同意する") {
                appState.isAgreed = true
            }
            .disabled(!agreed)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
