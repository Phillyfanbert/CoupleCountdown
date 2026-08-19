// AppGroupCache.swift — shared App Group read/write helpers for app <-> widget (DESIGN.md §5.2, §5.5, §6)

import Foundation

/// Shared cache written by the app and read by the widget through the
/// App Group container. Every sync mechanism in §5.2 that receives fresh
/// server data is supposed to write through here and then trigger a
/// widget timeline reload — that convention lives in the app target's
/// SyncCoordinator, not here; this type is just the storage primitive.
///
/// If App Groups turns out not to provision under a free Personal Team
/// (§5.5's fallback tree), `UserDefaults(suiteName:)` simply returns nil
/// and every read/write below becomes a silent no-op — callers should
/// already treat a nil `read()` as "no cached data yet," which degrades
/// correctly rather than crashing.
public struct AppGroupCache {
    private let defaults: UserDefaults?
    private let stateKey = "cachedRelationshipState"

    /// `suiteName` must match the App Group identifier configured in both
    /// the app and widget targets' entitlements (DESIGN.md §5.6) — that
    /// identifier doesn't exist yet since no real Xcode project exists,
    /// so it's passed in rather than hardcoded here.
    public init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName)
    }

    public func write(_ state: RelationshipState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults?.set(data, forKey: stateKey)
    }

    public func read() -> RelationshipState? {
        guard let data = defaults?.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(RelationshipState.self, from: data)
    }
}
