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
                            do {
                                try await authService.signInIfNeeded()
                            } catch {
                                // Deliberately not swallowed via `try?` —
                                // a silent failure here means the app is
                                // stuck on this screen forever with no
                                // way to tell why (caught exactly this
                                // way during CI Simulator verification).
                                print("AuthService.signInIfNeeded() failed: \(error)")
                            }
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
