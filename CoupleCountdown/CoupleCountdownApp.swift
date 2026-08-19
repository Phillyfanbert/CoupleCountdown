// CoupleCountdownApp.swift — @main app entry point (DESIGN.md §5.6)

import SwiftUI
import FirebaseCore
import CoupleCountdownKit

@main
struct CoupleCountdownApp: App {
    // Shared App Group suite (§5.6) rather than the default local suite,
    // so the widget can read the same coupleId this device persists
    // (DESIGN.md §5.3 point 7).
    @AppStorage("coupleId", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var coupleId: String = ""

    @StateObject private var authService = AuthService()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.uid == nil {
                    ProgressView("Signing in…")
                        .task {
                            try? await authService.signInIfNeeded()
                        }
                } else if coupleId.isEmpty {
                    OnboardingView(coupleId: $coupleId)
                } else {
                    CountdownView(coupleId: coupleId, uid: authService.uid!)
                }
            }
            .environmentObject(authService)
        }
    }
}
