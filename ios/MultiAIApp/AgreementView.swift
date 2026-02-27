import SwiftUI

struct AgreementView: View {
    @EnvironmentObject var appState: AppState
    @State private var agreed = false

    private let termsURL = URL(string: "https://ufjkkaio.github.io/MultiAI/terms-of-use.html")
    private let privacyURL = URL(string: "https://ufjkkaio.github.io/MultiAI/privacy-policy.html")

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 44))
                            .foregroundStyle(AppTheme.accent)

                        Text("利用規約とプライバシーポリシー")
                            .font(AppTheme.titleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("続行する前に、以下の内容に同意してください")
                            .font(AppTheme.bodyFont)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.top, 40)

                    VStack(spacing: 12) {
                        if let terms = termsURL {
                            Link(destination: terms) {
                                HStack {
                                    Image(systemName: "doc.text")
                                    Text("利用規約")
                                        .font(AppTheme.headlineFont)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                }
                                .foregroundStyle(AppTheme.accent)
                                .padding()
                                .background(AppTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        if let privacy = privacyURL {
                            Link(destination: privacy) {
                                HStack {
                                    Image(systemName: "hand.raised")
                                    Text("プライバシーポリシー")
                                        .font(AppTheme.headlineFont)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                }
                                .foregroundStyle(AppTheme.accent)
                                .padding()
                                .background(AppTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    HStack(alignment: .top, spacing: 14) {
                        Toggle("", isOn: $agreed)
                            .labelsHidden()
                            .tint(AppTheme.accent)

                        Text("利用規約とプライバシーポリシーに同意する")
                            .font(AppTheme.bodyFont)
                            .foregroundStyle(AppTheme.textPrimary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)

                    Button {
                        appState.isAgreed = true
                    } label: {
                        Text("同意して続ける")
                            .font(AppTheme.headlineFont)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(agreed ? AppTheme.accent : AppTheme.surfaceElevated)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!agreed)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}
