// PingInbox.swift — the partner's "thinking of you" pings waiting to be seen (DESIGN.md §7.1)

import Foundation
import WidgetKit
import FirebaseFirestore
import CoupleCountdownKit

/// Watches recent pings while the app is open and keeps the partner's
/// unseen ones — what the countdown screen's card shows. Also keeps the
/// widget's copy of the newest one current, so a ping dismissed here (or on
/// the web) leaves the Home Screen too.
@MainActor
final class PingInbox: ObservableObject {
    /// Newest first.
    @Published private(set) var unseen: [ThinkingOfYouPing] = []

    private let firestore: FirestoreService
    private let cache: AppGroupCache
    private let coupleId: String
    private let uid: String
    private let widgetKind: String
    private var listener: ListenerRegistration?
    private var latest: [ThinkingOfYouPing] = []
    /// Dismissed here, before the server has the seenAt write.
    private var dismissed: Set<String> = []

    init(firestore: FirestoreService, cache: AppGroupCache, coupleId: String, uid: String, widgetKind: String) {
        self.firestore = firestore
        self.cache = cache
        self.coupleId = coupleId
        self.uid = uid
        self.widgetKind = widgetKind
    }

    /// Attach while the app is foregrounded, like SyncCoordinator's listener.
    /// Restarting also moves the "recent" window forward.
    func startListening() {
        stopListening()
        listener = firestore.listenToRecentPings(coupleId: coupleId) { [weak self] pings in
            Task { @MainActor in
                self?.latest = pings
                self?.refresh()
            }
        }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    /// Dismisses everything the card is showing, on every device on this
    /// account. Hides it here straight away; brings it back if the write fails.
    func markAllSeen() async throws {
        let ids = unseen.map(\.id)
        guard !ids.isEmpty else { return }
        dismissed.formUnion(ids)
        refresh()
        do {
            try await firestore.markPingsSeen(ids: ids, coupleId: coupleId)
            // Again now the server has it: a widget refresh that raced the
            // write could have re-cached the ping.
            cache.writeUnseenPing(unseen.first)
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        } catch {
            dismissed.subtract(ids)
            refresh()
            throw error
        }
    }

    private func refresh() {
        unseen = ThinkingOfYouPing.unseen(latest, for: uid).filter { !dismissed.contains($0.id) }
        if cache.readUnseenPing()?.id != unseen.first?.id {
            cache.writeUnseenPing(unseen.first)
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }
    }
}
