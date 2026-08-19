// WidgetAuthTokenProvider.swift — mints a short-lived ID token from the Keychain-shared refresh token (DESIGN.md §5.5)

import Foundation
import CoupleCountdownKit

/// Mints a fresh Firebase ID token from the Anonymous Auth refresh token
/// the app persisted into the shared Keychain (§5.5) — plain REST against
/// Google's token endpoint, no Firebase Auth SDK bundled into the widget
/// extension.
struct WidgetAuthTokenProvider {
    private let keychain: KeychainStore
    /// Firebase Web API key — public, identifies the Firebase project
    /// rather than authenticating anything by itself, so it's safe to
    /// embed. Placeholder until the real Firebase project exists (§5.7).
    private let apiKey: String

    init(keychainAccessGroup: String = SharedIdentifiers.keychainAccessGroup, apiKey: String) {
        self.keychain = KeychainStore(accessGroup: keychainAccessGroup)
        self.apiKey = apiKey
    }

    /// Never throws — returns nil on any failure (missing token, no
    /// network, bad response), and WidgetFirestoreClient treats a nil
    /// token as "fall back to the App Group cache" per §5.5's
    /// failure-mode behavior.
    func fetchIDToken() async -> String? {
        guard let refreshToken = keychain.read() else { return nil }

        guard let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "grant_type=refresh_token&refresh_token=\(refreshToken)"
        request.httpBody = body.data(using: .utf8)

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let idToken = json["id_token"] as? String
        else { return nil }

        return idToken
    }
}
