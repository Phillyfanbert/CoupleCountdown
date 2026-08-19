// AuthService.swift — Firebase Anonymous Auth sign-in + refresh-token persistence to Keychain (DESIGN.md §5.3 point 1, §5.5)

import Foundation
import FirebaseAuth
import CoupleCountdownKit

/// Signs in anonymously on first launch (DESIGN.md §5.3 point 1) and
/// mirrors the refresh token into the shared Keychain so the widget
/// extension can mint its own short-lived ID tokens (§5.5) without
/// bundling the Firebase Auth SDK into the extension.
///
/// UNVERIFIED (no Xcode on this machine to compile against — see DESIGN.md
/// v0.3 discussion): `User.refreshToken` is assumed to be a public
/// `String?` property on FirebaseAuth's `User` type; double-check against
/// the actual SDK on first real build.
@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var uid: String?

    private let keychain: KeychainStore

    init(keychainAccessGroup: String = SharedIdentifiers.keychainAccessGroup) {
        self.keychain = KeychainStore(accessGroup: keychainAccessGroup)
        self.uid = Auth.auth().currentUser?.uid
    }

    /// Call once on app launch, before deciding whether to show
    /// onboarding or the countdown screen.
    func signInIfNeeded() async throws {
        if let user = Auth.auth().currentUser {
            uid = user.uid
            persistRefreshToken(for: user)
            return
        }
        let result = try await Auth.auth().signInAnonymously()
        uid = result.user.uid
        persistRefreshToken(for: result.user)
    }

    private func persistRefreshToken(for user: User) {
        guard let refreshToken = user.refreshToken else { return }
        keychain.write(refreshToken)
    }
}
