// AccountSessionView.swift — routes a signed-in account to onboarding or the countdown

import SwiftUI
import WidgetKit
import FirebaseFirestore
import CoupleCountdownKit

/// Watches the account record (users/{uid}) for as long as the account is
/// signed in on this device. Pairing, cancelling, or joining from any device
/// on the same account — including the web client — moves this one along.
@MainActor
final class AccountSession: ObservableObject {
    enum State: Equatable {
        case loading
        case ready(FirestoreService.AccountProfile)
        case failed
    }

    @Published private(set) var state: State = .loading

    let uid: String
    private let firestore = FirestoreService()
    private var registration: ListenerRegistration?

    init(uid: String) {
        self.uid = uid
    }

    func start() {
        guard registration == nil else { return }
        registration = firestore.listenToProfile(uid: uid) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let profile):
                    self?.state = .ready(profile)
                case .failure(let error):
                    print("Account listener failed: \(error)")
                    self?.state = .failed
                }
            }
        }
    }

    func restart() {
        registration?.remove()
        registration = nil
        state = .loading
        start()
    }

    func stop() {
        registration?.remove()
        registration = nil
    }
}

struct AccountSessionView: View {
    let uid: String

    @EnvironmentObject private var authService: AuthService
    @StateObject private var session: AccountSession

    /// The widget can't query the account itself, so the current pairing is
    /// mirrored into the shared App Group suite for it (§5.6).
    @AppStorage("coupleId", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var widgetCoupleId: String = ""

    /// True while the create-pairing screen is showing a freshly generated
    /// code. The account already records the new pairing by then (so other
    /// devices pick it up), but this device stays on the code until the user
    /// taps Continue — otherwise the code would vanish before it could be
    /// read or shared.
    @State private var holdingNewCode = false

    init(uid: String) {
        self.uid = uid
        _session = StateObject(wrappedValue: AccountSession(uid: uid))
    }

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView("Loading your account…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .themedBackground()
            case .failed:
                VStack(spacing: 16) {
                    Text("Couldn't load your account")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                    Text("Check your connection and try again.")
                        .foregroundStyle(.secondary)
                    Button("Try again") { session.restart() }
                        .buttonStyle(.borderedProminent)
                    Button("Sign out") { authService.signOut() }
                    if let signOutError = authService.signOutError {
                        Text(signOutError).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .themedBackground()
            case .ready(let profile):
                if let coupleId = profile.coupleId, !coupleId.isEmpty, !holdingNewCode {
                    CountdownView(coupleId: coupleId, uid: uid, displayName: profile.displayName)
                        .id(coupleId) // fresh sync state if the pairing changes
                } else {
                    OnboardingView(uid: uid, profileName: profile.displayName, holdingNewCode: $holdingNewCode)
                }
            }
        }
        .task { session.start() }
        .onDisappear { session.stop() }
        .onChange(of: session.state) { _, newState in
            guard case .ready(let profile) = newState else { return }
            let coupleId = profile.coupleId ?? ""
            if widgetCoupleId != coupleId {
                // The cached state belongs to the old pairing (or none) —
                // drop it so the widget can't keep showing it.
                AppGroupCache(suiteName: SharedIdentifiers.appGroup).clear()
                widgetCoupleId = coupleId
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }
}
