import SwiftUI
import StoreKit

struct SubscriptionPaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 48))
                            .foregroundStyle(AppTheme.accent)

                        Text("MultiAI プレミアム")
                            .font(AppTheme.titleFont)
                            .foregroundStyle(AppTheme.textPrimary)

                        Text("ChatGPT と Gemini の両方に同時質問し、\n無制限にご利用いただけます。")
                            .font(AppTheme.bodyFont)
                            .foregroundStyle(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 32)

                    if let product = subscriptionManager.products.first {
                        Text(product.displayPrice)
                            .font(.system(size: 36, design: .rounded))
                            .fontWeight(.bold)
                            .foregroundStyle(AppTheme.accent)
                        Text("/ 月")
                            .font(AppTheme.bodyFont)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    if let err = subscriptionManager.errorMessage {
                        Text(err)
                            .font(AppTheme.captionFont)
                            .foregroundStyle(AppTheme.errorRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    VStack(spacing: 12) {
                        Button {
                            Task { await subscriptionManager.purchase() }
                        } label: {
                            HStack {
                                if subscriptionManager.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("購入する")
                                        .font(AppTheme.headlineFont)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(AppTheme.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(subscriptionManager.isLoading || subscriptionManager.products.isEmpty)

                        Button {
                            Task { await subscriptionManager.restore() }
                        } label: {
                            Text("購入を復元")
                                .font(AppTheme.bodyFont)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .disabled(subscriptionManager.isLoading)
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)

                    Spacer()
                }
            }
            .onAppear {
                Task { await subscriptionManager.loadProducts() }
            }
            .onChange(of: subscriptionManager.isActive) { _, active in
                if active {
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
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
