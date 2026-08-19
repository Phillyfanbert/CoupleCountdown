// WidgetFirestoreClient.swift — plain URLSession Firestore REST fetch, no Firebase SDK (DESIGN.md §5.2 #4, §5.5)

import Foundation
import CoupleCountdownKit

/// The widget's own independent data fetch (§5.2 mechanism #4) — plain
/// REST against the Firestore document API, no Firebase SDK bundled into
/// the extension to stay under its memory ceiling. Never throws; every
/// failure path returns nil so the caller falls back to the App Group
/// cache (§5.5's failure-mode behavior — the widget should never show an
/// error state, only ever "last known good").
struct WidgetFirestoreClient {
    private let projectId: String
    private let tokenProvider: WidgetAuthTokenProvider

    init(projectId: String, tokenProvider: WidgetAuthTokenProvider) {
        self.projectId = projectId
        self.tokenProvider = tokenProvider
    }

    func fetchRelationshipState(coupleId: String) async -> RelationshipState? {
        guard let idToken = await tokenProvider.fetchIDToken() else { return nil }
        guard let url = URL(
            string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/couples/\(coupleId)"
        ) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5 // short, explicit timeout per §5.5

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else { return nil }

        return Self.parse(data)
    }

    /// Firestore's REST API returns typed field values
    /// (`{"stringValue": "..."}`, `{"timestampValue": "..."}`, etc.) —
    /// this unwraps just the fields RelationshipState needs.
    private static func parse(_ data: Data) -> RelationshipState? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let fields = json["fields"] as? [String: Any],
            let statusString = string(fields["status"]),
            let status = RelationshipState.Status(rawValue: statusString),
            let participantUIDs = stringArray(fields["participantUIDs"]),
            let lastUpdatedBy = string(fields["lastUpdatedBy"]),
            let lastUpdatedAt = timestamp(fields["lastUpdatedAt"])
        else { return nil }

        return RelationshipState(
            status: status,
            nextMeetupDate: timestamp(fields["nextMeetupDate"]),
            participantUIDs: participantUIDs,
            partnerProfiles: parsePartnerProfiles(fields["partnerProfiles"]),
            lastUpdatedBy: lastUpdatedBy,
            lastUpdatedAt: lastUpdatedAt
        )
    }

    private static func string(_ value: Any?) -> String? {
        (value as? [String: Any])?["stringValue"] as? String
    }

    private static func timestamp(_ value: Any?) -> Date? {
        guard let iso = (value as? [String: Any])?["timestampValue"] as? String else { return nil }
        return ISO8601DateFormatter().date(from: iso)
    }

    private static func stringArray(_ value: Any?) -> [String]? {
        guard let arrayValue = (value as? [String: Any])?["arrayValue"] as? [String: Any] else { return nil }
        let values = arrayValue["values"] as? [[String: Any]] ?? []
        return values.compactMap { $0["stringValue"] as? String }
    }

    private static func parsePartnerProfiles(_ value: Any?) -> [String: PartnerProfile] {
        guard
            let mapValue = (value as? [String: Any])?["mapValue"] as? [String: Any],
            let fields = mapValue["fields"] as? [String: Any]
        else { return [:] }

        var result: [String: PartnerProfile] = [:]
        for (uid, entry) in fields {
            guard
                let entryMap = (entry as? [String: Any])?["mapValue"] as? [String: Any],
                let entryFields = entryMap["fields"] as? [String: Any],
                let displayName = string(entryFields["displayName"]),
                let timeZoneIdentifier = string(entryFields["timeZoneIdentifier"])
            else { continue }
            result[uid] = PartnerProfile(displayName: displayName, timeZoneIdentifier: timeZoneIdentifier)
        }
        return result
    }
}
