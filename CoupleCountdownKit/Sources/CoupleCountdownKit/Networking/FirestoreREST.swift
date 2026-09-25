// FirestoreREST.swift — decoding Firestore REST responses for the widget (DESIGN.md §5.2 #4, §5.5)

import Foundation

/// Decodes the Firestore REST API's typed JSON (`{"stringValue": …}`,
/// `{"timestampValue": …}`, …) into the Kit's models. Lives here rather than
/// in the widget target so it's unit-tested in CI — the widget itself can't
/// be exercised there, and a decoding bug in it fails silently (the widget
/// just falls back to the app's cache).
public enum FirestoreREST {

    /// An RFC 3339 `timestampValue`. Firestore sends fractional seconds of
    /// any length ("…:29.519Z", "…:30.209719Z") or none at all; a plain
    /// `ISO8601DateFormatter` accepts only the no-fraction form, which made
    /// every widget fetch fail to decode.
    public static func timestamp(_ value: String) -> Date? {
        let parser = ISO8601DateFormatter()
        guard let dot = value.firstIndex(of: "."),
              let end = value[dot...].firstIndex(where: { !$0.isNumber && $0 != "." })
        else { return parser.date(from: value) }
        guard let whole = parser.date(from: String(value[..<dot]) + String(value[end...])),
              let fraction = Double("0" + String(value[dot..<end]))
        else { return nil }
        return whole.addingTimeInterval(fraction)
    }

    /// A `couples/{coupleId}` document, as returned by a REST GET.
    public static func relationshipState(fromDocument data: Data) -> RelationshipState? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let fields = json["fields"] as? [String: Any],
            let statusString = string(fields["status"]),
            let status = RelationshipState.Status(rawValue: statusString),
            let participantUIDs = stringArray(fields["participantUIDs"]),
            let lastUpdatedBy = string(fields["lastUpdatedBy"]),
            let lastUpdatedAt = date(fields["lastUpdatedAt"])
        else { return nil }

        return RelationshipState(
            status: status,
            nextMeetupDate: date(fields["nextMeetupDate"]),
            participantUIDs: participantUIDs,
            partnerProfiles: partnerProfiles(fields["partnerProfiles"]),
            lastUpdatedBy: lastUpdatedBy,
            lastUpdatedAt: lastUpdatedAt,
            pairedAt: date(fields["pairedAt"])
        )
    }

    /// The pings in a `:runQuery` response. Nil if the response isn't a
    /// runQuery result at all; an empty match comes back as rows holding
    /// only a `readTime`, which decode to an empty array.
    public static func pings(fromRunQuery data: Data) -> [ThinkingOfYouPing]? {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard
                let document = row["document"] as? [String: Any],
                let name = document["name"] as? String,
                let fields = document["fields"] as? [String: Any],
                let sentBy = string(fields["sentBy"]),
                let sentAt = date(fields["sentAt"])
            else { return nil }
            return ThinkingOfYouPing(
                id: String(name.split(separator: "/").last ?? ""),
                sentBy: sentBy,
                sentAt: sentAt,
                expiresAt: date(fields["expiresAt"]),
                seenAt: date(fields["seenAt"])
            )
        }
    }

    /// The `:runQuery` body for pings sent after `since`, newest first.
    public static func recentPingsQuery(since: Date) -> Data {
        let sentAt: [String: Any] = ["fieldPath": "sentAt"]
        let filter: [String: Any] = [
            "field": sentAt,
            "op": "GREATER_THAN",
            "value": ["timestampValue": ISO8601DateFormatter().string(from: since)],
        ]
        let order: [String: Any] = ["field": sentAt, "direction": "DESCENDING"]
        let structuredQuery: [String: Any] = [
            "from": [["collectionId": "pings"]],
            "where": ["fieldFilter": filter],
            "orderBy": [order],
            "limit": 20,
        ]
        return (try? JSONSerialization.data(withJSONObject: ["structuredQuery": structuredQuery])) ?? Data()
    }

    // MARK: - Typed values

    private static func string(_ value: Any?) -> String? {
        (value as? [String: Any])?["stringValue"] as? String
    }

    private static func date(_ value: Any?) -> Date? {
        ((value as? [String: Any])?["timestampValue"] as? String).flatMap(timestamp)
    }

    private static func stringArray(_ value: Any?) -> [String]? {
        guard let arrayValue = (value as? [String: Any])?["arrayValue"] as? [String: Any] else { return nil }
        let values = arrayValue["values"] as? [[String: Any]] ?? []
        return values.compactMap { $0["stringValue"] as? String }
    }

    private static func partnerProfiles(_ value: Any?) -> [String: PartnerProfile] {
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
