// CoupleCountdownApp.swift — @main app entry point (DESIGN.md §5.6)

import SwiftUI
import WidgetKit
import FirebaseCore
import CoupleCountdownKit

@main
struct CoupleCountdownApp: App {
    @StateObject private var authService: AuthService

    /// False only while the XCUITest reset hook (below) is still running.
    @State private var isReady: Bool

    private static let isUITestReset = ProcessInfo.processInfo.arguments.contains("-uiTestReset")

    /// UI tests sign up with addresses on this reserved, undeliverable
    /// domain; the reset hook only ever deletes accounts on it.
    static let uiTestEmailDomain = "@test.couplecountdown.invalid"

    init() {
        FirebaseApp.configure()
        // Gated behind a launch argument only XCUITest ever passes (see
        // CoupleCountdownUITests): clears device-side state so each test
        // starts from a genuinely fresh, signed-out app.
        if Self.isUITestReset {
            UserDefaults(suiteName: SharedIdentifiers.appGroup)?.removePersistentDomain(forName: SharedIdentifiers.appGroup)
            KeychainStore(accessGroup: SharedIdentifiers.keychainAccessGroup).delete()
        }
        _authService = StateObject(wrappedValue: AuthService())
        _isReady = State(initialValue: !Self.isUITestReset)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !isReady {
                    ProgressView()
                } else if let uid = authService.uid, !authService.isFinishingSignUp {
                    AccountSessionView(uid: uid)
                        .id(uid) // a different account gets a fresh session
                } else {
                    SignInView()
                }
            }
            .environmentObject(authService)
            .task {
                guard !isReady else { return }
                await resetForUITests()
                isReady = true
            }
            .onChange(of: authService.uid) { _, uid in
                // Signed out: the widget shouldn't keep showing this account's pairing.
                if uid == nil {
                    UserDefaults(suiteName: SharedIdentifiers.appGroup)?.removeObject(forKey: "coupleId")
                    AppGroupCache(suiteName: SharedIdentifiers.appGroup).clear()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
    }

    /// Signs out whatever the previous test left signed in — and deletes it if
    /// it's a UI-test account, so CI runs don't pile up test users in the real
    /// Firebase project. Never touches an account outside the test domain.
    private func resetForUITests() async {
        if let uid = authService.uid,
           authService.currentAccountEmail?.hasSuffix(Self.uiTestEmailDomain) == true {
            try? await FirestoreService().deleteProfile(uid: uid)
            do {
                try await authService.deleteCurrentAccount()
            } catch {
                print("UI-test account cleanup failed: \(error)")
            }
        }
        authService.signOut()
    }
}
