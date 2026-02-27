import SwiftUI

struct SideMenuView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    var onSubscriptionTap: () -> Void

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
                                Text("無料プラン")
                                    .font(AppTheme.captionFont)
                                    .foregroundStyle(AppTheme.textSecondary)
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
        }
    }
}
