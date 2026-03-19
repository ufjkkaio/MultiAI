import SwiftUI

struct SideMenuView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    var onSubscriptionTap: () -> Void
    @State private var showDeleteAccountAlert = false
    @State private var deleteErrorMessage: String?

    private let termsURL = URL(string: "https://ufjkkaio.github.io/MultiAI/terms-of-use.html")
    private let privacyURL = URL(string: "https://ufjkkaio.github.io/MultiAI/privacy-policy.html")

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(AppTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("アカウント")
                                .font(AppTheme.headlineFont)
                                .foregroundStyle(AppTheme.textPrimary)
                            if appState.isSubscribed {
                                Label("プレミアム会員", systemImage: "checkmark.seal.fill")
                                    .font(AppTheme.captionFont)
                                    .foregroundStyle(AppTheme.successGreen)
                            } else {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("無料プラン")
                                        .font(AppTheme.captionFont)
                                        .foregroundStyle(AppTheme.textSecondary)
                                    if let n = subscriptionManager.freeRemaining {
                                        Text("あと\(n)通無料")
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.textSecondary)
                                    }
                                }
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(AppTheme.surface)
                    .listRowSeparator(.hidden)
                }

                Section("メニュー") {
                    if !appState.isSubscribed {
                        Button {
                            dismiss()
                            onSubscriptionTap()
                        } label: {
                            Label("サブスクリプション", systemImage: "crown.fill")
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .listRowBackground(AppTheme.surface)
                    }

                    if let terms = termsURL {
                        Link(destination: terms) {
                            Label("利用規約", systemImage: "doc.text")
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                    if let privacy = privacyURL {
                        Link(destination: privacy) {
                            Label("プライバシーポリシー", systemImage: "hand.raised")
                                .foregroundStyle(AppTheme.textPrimary)
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteAccountAlert = true
                    } label: {
                        Label("Delete Account", systemImage: "person.crop.circle.badge.minus")
                    }
                    .listRowBackground(AppTheme.surface)

                    Button(role: .destructive) {
                        appState.logout()
                        dismiss()
                    } label: {
                        Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .listRowBackground(AppTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("メニュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
            .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("Your account and related data will be permanently deleted. This action cannot be undone. " +
                     "Your App Store subscription will not be canceled automatically.")
            }
            .alert("Error", isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )) {
                Button("Close", role: .cancel) {}
            } message: {
                Text(deleteErrorMessage ?? "")
            }
        }
    }

    private func deleteAccount() async {
        guard let token = appState.authToken else { return }
        guard let url = URL(string: APIClient.baseURL + "/user/account") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.allHTTPHeaderFields = APIClient.authHeader(token)

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let code = (resp as? HTTPURLResponse)?.statusCode, (200 ... 299).contains(code) else {
                deleteErrorMessage = "Failed to delete account. Please try again later."
                return
            }
            appState.logout()
            dismiss()
        } catch {
            deleteErrorMessage = "Failed to delete account. Please try again later."
        }
    }
}
