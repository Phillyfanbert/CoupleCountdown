// CountdownTimelineProvider.swift — single-entry, ~30-min-policy timeline provider (DESIGN.md §6 "Timeline provider entries/policy")

import WidgetKit
import CoupleCountdownKit

struct CountdownEntry: TimelineEntry {
    let date: Date
    let state: RelationshipState?
}

struct CountdownTimelineProvider: TimelineProvider {
    private let cache = AppGroupCache(suiteName: SharedIdentifiers.appGroup)

    // Placeholders until the real Firebase project exists (§5.7) — the
    // project ID and Web API key aren't secrets, but they don't exist yet.
    private let client = WidgetFirestoreClient(
        projectId: "REPLACE_WITH_FIREBASE_PROJECT_ID",
        tokenProvider: WidgetAuthTokenProvider(apiKey: "REPLACE_WITH_FIREBASE_WEB_API_KEY")
    )

    func placeholder(in context: Context) -> CountdownEntry {
        // First-run empty state: no cache yet if the widget's added
        // before pairing completes (§6) — `state` being nil here is
        // exactly that case, not an error.
        CountdownEntry(date: Date(), state: cache.read())
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        completion(CountdownEntry(date: Date(), state: cache.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        Task {
            let coupleId = UserDefaults(suiteName: SharedIdentifiers.appGroup)?.string(forKey: "coupleId")

            var state = cache.read()
            if let coupleId, !coupleId.isEmpty,
               let fresh = await client.fetchRelationshipState(coupleId: coupleId) {
                state = fresh
                cache.write(fresh)
            }
            // If the fetch failed for any reason, `state` just stays
            // whatever was already in the cache — never an error state
            // (§5.5 failure-mode behavior).

            let entry = CountdownEntry(date: Date(), state: state)
            // Single entry — Text(timerInterval:) handles the digit
            // ticking on its own, so there's no need to pre-generate a
            // series of future entries. `.after(~30 min)` is a request,
            // not a guarantee; WidgetKit's actual cadence is still
            // OS-controlled (§5.2 #4) — `.never` would starve updates,
            // `.atEnd` with one entry risks hammering the refresh budget
            // (§6).
            let nextRefresh = Date().addingTimeInterval(30 * 60)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}
