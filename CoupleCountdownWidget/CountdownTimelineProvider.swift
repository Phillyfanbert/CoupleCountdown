// CountdownTimelineProvider.swift — ~30-min-policy timeline provider (DESIGN.md §6 "Timeline provider entries/policy")

import WidgetKit
import CoupleCountdownKit

struct CountdownEntry: TimelineEntry {
    let date: Date
    let state: RelationshipState?
    /// The newest "thinking of you" from the partner not yet seen (§7.1).
    var unseenPing: ThinkingOfYouPing? = nil
}

struct CountdownTimelineProvider: TimelineProvider {
    private let cache = AppGroupCache(suiteName: SharedIdentifiers.appGroup)

    // Real values from the Firebase project (couplecountdown-7715c) —
    // neither is a secret (DESIGN.md §5.7 discussion, Firebase's own docs:
    // the Web API key is a public identifier, not a credential; access
    // control comes entirely from the tested Security Rules).
    private let client = WidgetFirestoreClient(projectId: "couplecountdown-7715c")
    private let tokenProvider = WidgetAuthTokenProvider(apiKey: "AIzaSyCCo8NgjVwz6-P1lW6H1CKqGadyKwSA384")

    func placeholder(in context: Context) -> CountdownEntry {
        // First-run empty state: no cache yet if the widget's added
        // before pairing completes (§6) — `state` being nil here is
        // exactly that case, not an error.
        cachedEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        completion(cachedEntry())
    }

    private func cachedEntry() -> CountdownEntry {
        let state = cachedStateIfPaired()
        return CountdownEntry(date: Date(), state: state, unseenPing: state == nil ? nil : cache.readUnseenPing())
    }

    /// The app removes the App Group coupleId on sign-out and when the
    /// account leaves or cancels its pairing. Without a pairing the widget
    /// shows its not-paired state — it used to fall back to the cached
    /// state regardless, so the previous account's countdown stayed on the
    /// Home Screen indefinitely.
    private var currentCoupleId: String? {
        let coupleId = UserDefaults(suiteName: SharedIdentifiers.appGroup)?.string(forKey: "coupleId")
        return (coupleId?.isEmpty == false) ? coupleId : nil
    }

    private func cachedStateIfPaired() -> RelationshipState? {
        currentCoupleId == nil ? nil : cache.read()
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        Task {
            var state = cachedStateIfPaired()
            var unseenPing = state == nil ? nil : cache.readUnseenPing()
            if let coupleId = currentCoupleId, let session = await tokenProvider.fetchSession() {
                if let fresh = await client.fetchRelationshipState(coupleId: coupleId, session: session) {
                    state = fresh
                    cache.write(fresh)
                }
                // Without push, the widget is how a partner who hasn't
                // opened the app finds out someone's thinking of them.
                if let pings = await client.fetchRecentPings(coupleId: coupleId, session: session) {
                    unseenPing = ThinkingOfYouPing.unseen(pings, for: session.uid).first
                    cache.writeUnseenPing(unseenPing)
                }
            }
            // If a fetch failed for any reason, its value just stays
            // whatever was already in the cache — never an error state
            // (§5.5 failure-mode behavior).

            let entry = CountdownEntry(date: Date(), state: state, unseenPing: unseenPing)
            // A second entry at the meetup moment, so the widget switches to
            // "The day is here" on time instead of sitting at 0:00 until the
            // next refresh.
            var entries = [entry]
            if let state, state.status == .apart, let meetup = state.nextMeetupDate, meetup > entry.date {
                entries.append(CountdownEntry(date: meetup, state: state, unseenPing: unseenPing))
            }
            // Otherwise one entry — Text(timerInterval:) handles the digit
            // ticking on its own, so there's no need to pre-generate a
            // series of future entries. `.after(~30 min)` is a request,
            // not a guarantee; WidgetKit's actual cadence is still
            // OS-controlled (§5.2 #4) — `.never` would starve updates,
            // `.atEnd` with one entry risks hammering the refresh budget
            // (§6).
            let nextRefresh = Date().addingTimeInterval(30 * 60)
            completion(Timeline(entries: entries, policy: .after(nextRefresh)))
        }
    }
}
