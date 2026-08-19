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
        guard let fetched = try? await firestore.fetchCouple(coupleId: coupleId) else { return }
        publish(fetched)
    }

    /// Mechanism #1 (§5.2): attach while the app is foregrounded, detach
    /// on background — call sites are the app's scenePhase observer.
    func startListening() {
        stopListening()
        listener = firestore.listenToCouple(coupleId: coupleId) { [weak self] state in
            Task { @MainActor in
                self?.publish(state)
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    private func publish(_ newState: RelationshipState) {
        state = newState
        cache.write(newState)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
