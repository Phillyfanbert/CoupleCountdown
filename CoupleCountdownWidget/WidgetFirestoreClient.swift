// WidgetFirestoreClient.swift — plain URLSession Firestore REST fetch, no Firebase SDK (DESIGN.md §5.2 #4, §5.5)

import Foundation
import CoupleCountdownKit

/// The widget's own independent data fetch (§5.2 mechanism #4) — plain
/// REST against the Firestore API, no Firebase SDK bundled into the
/// extension to stay under its memory ceiling. Never throws; every failure
/// path returns nil so the caller falls back to the App Group cache (§5.5's
/// failure-mode behavior — the widget should never show an error state,
/// only ever "last known good"). Response decoding lives in
/// CoupleCountdownKit's `FirestoreREST`, where it's unit-tested.
struct WidgetFirestoreClient {
    private let projectId: String

    init(projectId: String) {
        self.projectId = projectId
    }

    func fetchRelationshipState(coupleId: String, session: WidgetSession) async -> RelationshipState? {
        guard let url = URL(string: coupleURL(coupleId)) else { return nil }
        guard let data = await send(URLRequest(url: url), session: session) else { return nil }
        return FirestoreREST.relationshipState(fromDocument: data)
    }

    /// Pings from the last `ThinkingOfYouPing.lifetime` (both partners'),
    /// or nil if the fetch failed.
    func fetchRecentPings(coupleId: String, session: WidgetSession, now: Date = Date()) async -> [ThinkingOfYouPing]? {
        guard let url = URL(string: "\(coupleURL(coupleId)):runQuery") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = FirestoreREST.recentPingsQuery(since: now.addingTimeInterval(-ThinkingOfYouPing.lifetime))
        guard let data = await send(request, session: session) else { return nil }
        return FirestoreREST.pings(fromRunQuery: data)
    }

    private func coupleURL(_ coupleId: String) -> String {
        "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/couples/\(coupleId)"
    }

    private func send(_ request: URLRequest, session: WidgetSession) async -> Data? {
        var request = request
        request.setValue("Bearer \(session.idToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5 // short, explicit timeout per §5.5
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else { return nil }
        return data
    }
}
