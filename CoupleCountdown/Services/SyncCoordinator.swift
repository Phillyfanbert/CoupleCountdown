// SyncCoordinator.swift — the sync pipeline convention: cache write + widget reload on every fresh state (DESIGN.md §5.2)

import Foundation
import WidgetKit
import FirebaseFirestore
import CoupleCountdownKit

/// Implements the "sync pipeline convention" from DESIGN.md §5.2: any
/// time fresh RelationshipState arrives — from the realtime listener, a
/// one-shot fetch, or a local write this device just made itself — it
/// gets written to the App Group cache and the widget's timeline gets
/// reloaded. This is what makes the *acting* partner's own widget update
/// instantly, independent of the latency table in §5.4.
@MainActor
final class SyncCoordinator: ObservableObject {
    @Published private(set) var state: RelationshipState?
    /// Why there's nothing to show yet, if loading failed. Cleared as soon
    /// as any state arrives.
    @Published private(set) var loadProblem: LoadProblem?

    enum LoadProblem: Equatable {
        /// Offline, or the server couldn't be reached.
        case unreachable
        /// The rules refused: this account isn't in that pairing.
        case noAccess
    }

    private let firestore: FirestoreService
    private let cache: AppGroupCache
    private let coupleId: String
    private let widgetKind: String
    private var listener: ListenerRegistration?

    init(firestore: FirestoreService, cache: AppGroupCache, coupleId: String, widgetKind: String) {
        self.firestore = firestore
        self.cache = cache
        self.coupleId = coupleId
        self.widgetKind = widgetKind
    }

    /// Mechanism #2 (§5.2): call on launch/foreground, before attaching
    /// the listener, so opening the app is always immediately fresh. Also
    /// what call sites use after making a local write themselves (§5.2's
    /// sync pipeline convention).
    func fetchOnLaunch() async {
        do {
            publish(try await firestore.fetchCouple(coupleId: coupleId))
        } catch {
            // Keep showing what we have; only an empty screen needs to say why.
            if state == nil { loadProblem = Self.problem(for: error) }
        }
    }

    /// Mechanism #1 (§5.2): attach while the app is foregrounded, detach
    /// on background — call sites are the app's scenePhase observer.
    func startListening() {
        stopListening()
        listener = firestore.listenToCouple(coupleId: coupleId, onChange: { [weak self] state in
            Task { @MainActor in
                self?.publish(state)
            }
        }, onError: { [weak self] error in
            Task { @MainActor in
                guard let self, self.state == nil else { return }
                self.loadProblem = Self.problem(for: error)
            }
        })
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    /// Call right after a local write this device just made (status
    /// toggle, date change) succeeds, with the resulting state — this is
    /// what actually makes the acting partner's own widget update
    /// instantly per §5.2's sync pipeline convention. No network
    /// round-trip: `lastUpdatedAt` here is the local clock, not the
    /// server-resolved timestamp; the exact value arrives shortly after
    /// via the listener/next fetch and harmlessly overwrites this.
    /// Previously missing entirely — writes only reached the local
    /// widget by waiting for the listener to echo them back, which is
    /// exactly the network round-trip §5.2 says shouldn't be needed.
    func applyLocalWrite(_ state: RelationshipState) {
        publish(state)
    }

    private static func problem(for error: Error) -> LoadProblem {
        (error as? FirestoreErrorCode)?.code == .permissionDenied ? .noAccess : .unreachable
    }

    private func publish(_ newState: RelationshipState) {
        state = newState
        loadProblem = nil
        cache.write(newState)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
