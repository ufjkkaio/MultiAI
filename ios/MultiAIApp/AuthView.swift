import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @EnvironmentObject var appState: AppState
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 56))
                        .foregroundStyle(AppTheme.accent)

                    Text("MultiAI")
                        .font(.system(size: 32, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(AppTheme.textPrimary)

                    Text("ChatGPT と Gemini に同時に質問できる\nグループチャットアプリ")
                        .font(AppTheme.bodyFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                VStack(spacing: 16) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = []
                    } onCompletion: { result in
                        handleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    if let msg = errorMessage {
                        Text(msg)
                            .font(AppTheme.captionFont)
                            .foregroundStyle(AppTheme.errorRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.light)
    }

    private func handleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "認証情報を取得できませんでした"
                return
            }
            Task {
                await loginWithBackend(identityToken: identityToken)
            }
        case .failure(let err):
            errorMessage = err.localizedDescription
        }
    }

    private func loginWithBackend(identityToken: String) async {
        guard let url = URL(string: APIClient.baseURL + "/auth/apple") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["identityToken": identityToken])

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let res = try JSONDecoder().decode(AuthResponse.self, from: data)
            await MainActor.run {
                appState.authToken = res.token
                appState.userId = res.userId
                errorMessage = nil
            }
        } catch {
            await MainActor.run {
                errorMessage = "ログインに失敗しました"
            }
        }
    }
}

struct AuthResponse: Codable {
    let token: String
    let userId: String
}
