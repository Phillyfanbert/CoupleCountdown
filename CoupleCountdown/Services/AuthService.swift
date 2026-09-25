// AuthService.swift — email + password accounts + refresh-token persistence to Keychain (DESIGN.md §5.3, §5.5)

import Foundation
import FirebaseAuth
import CoupleCountdownKit

/// Identity is an email + password account, so one person can be signed in on
/// several devices at once (iPhone app, and the web client on a computer) and
/// every one of them sees the same pairing — which lives on the account in
/// `users/{uid}`, not on the device.
///
/// Also mirrors the refresh token into the shared Keychain so the widget
/// extension can mint its own short-lived ID tokens (§5.5) without bundling
/// the Firebase Auth SDK into the extension. Email/password refresh tokens
/// work there exactly like the anonymous ones did.
@MainActor
final class AuthService: ObservableObject {
    /// Set only for a real account. An anonymous session left over from
    /// before accounts existed counts as signed out until it's upgraded.
    @Published private(set) var uid: String?
    @Published private(set) var email: String?

    /// True while a new account's profile (name, carried-over pairing) is
    /// still being written — the app waits on it so the brand-new account
    /// doesn't flash the "what's your name?" step it's about to skip.
    @Published private(set) var isFinishingSignUp = false
    /// Shown next to the Sign out buttons when signing out didn't work.
    @Published private(set) var signOutError: String?

    private let keychain: KeychainStore
    private var stateListener: AuthStateDidChangeListenerHandle?

    init(keychainAccessGroup: String = SharedIdentifiers.keychainAccessGroup) {
        self.keychain = KeychainStore(accessGroup: keychainAccessGroup)
        apply(Auth.auth().currentUser)
        stateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.apply(user) }
        }
    }

    /// An anonymous identity from before accounts is still signed in here —
    /// creating an account will upgrade it in place (same uid).
    var hasLegacyAnonymousSession: Bool {
        Auth.auth().currentUser?.isAnonymous == true
    }

    /// Creates an account, or upgrades a leftover anonymous identity in place
    /// so a pairing made before accounts carries over. `saveProfile` runs
    /// before the app moves past the sign-in screen.
    func createAccount(
        email: String,
        password: String,
        saveProfile: (_ uid: String, _ upgradedAnonymous: Bool) async throws -> Void
    ) async throws {
        isFinishingSignUp = true
        defer { isFinishingSignUp = false }

        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        let uid: String
        // Decided before linking: Firebase mutates the user object in place,
        // so isAnonymous already reads false once the link succeeds.
        let upgradingAnonymous = Auth.auth().currentUser?.isAnonymous == true
        if upgradingAnonymous, let current = Auth.auth().currentUser {
            uid = try await current.link(with: credential).user.uid
        } else {
            uid = try await Auth.auth().createUser(withEmail: email, password: password).user.uid
        }
        apply(Auth.auth().currentUser)
        try await saveProfile(uid, upgradingAnonymous)
    }

    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        apply(result.user)
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    /// Signs out and forgets the widget's token. If Firebase couldn't sign
    /// out, this stays signed in and says so — it used to show the sign-in
    /// screen regardless (and delete the widget's token), and the account
    /// quietly came back on the next launch.
    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            print("AuthService.signOut() failed: \(error)")
            signOutError = "Couldn't sign out — try again."
            return
        }
        signOutError = nil
        keychain.delete()
        apply(nil)
    }

    /// Deletes the signed-in account. Only used by the UI-test reset hook
    /// (CoupleCountdownApp), so CI runs don't leave test accounts behind.
    func deleteCurrentAccount() async throws {
        try await Auth.auth().currentUser?.delete()
        keychain.delete()
        apply(nil)
    }

    var currentAccountEmail: String? {
        Auth.auth().currentUser?.email
    }

    private func apply(_ user: User?) {
        if let user, !user.isAnonymous {
            uid = user.uid
            email = user.email
            persistRefreshToken(for: user)
        } else {
            uid = nil
            email = nil
        }
    }

    private func persistRefreshToken(for user: User) {
        guard let refreshToken = user.refreshToken else { return }
        if !keychain.write(refreshToken) {
            // A silent failure here would mean the widget can never
            // authenticate independently, with no way to tell why (§5.5's
            // Keychain Sharing risk, §10).
            print("KeychainStore.write() failed to persist the refresh token — the widget will not be able to authenticate independently.")
        }
    }

    /// Plain-language message for a sign-in / sign-up failure.
    static func message(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == AuthErrors.domain,
              let code = AuthErrorCode(rawValue: nsError.code)
        else {
            return "Couldn't sign in — try again."
        }
        switch code {
        case .wrongPassword, .userNotFound, .invalidCredential:
            return "Email or password is incorrect."
        case .emailAlreadyInUse, .credentialAlreadyInUse:
            return "There's already an account with that email — sign in instead."
        case .invalidEmail:
            return "That doesn't look like an email address."
        case .weakPassword:
            return "Use at least 6 characters for your password."
        case .tooManyRequests:
            return "Too many attempts — wait a minute and try again."
        case .networkError:
            return "Can't reach the server — check your connection and try again."
        default:
            return "Couldn't sign in — try again."
        }
    }
}
