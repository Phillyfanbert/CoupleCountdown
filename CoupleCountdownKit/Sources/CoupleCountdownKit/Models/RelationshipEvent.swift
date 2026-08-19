// RelationshipEvent.swift — append-only together/apart history entry (DESIGN.md §5.1, §7)

import Foundation

/// Mirrors `couples/{coupleId}/events/{eventId}` (DESIGN.md §5.1). No TTL
/// on this collection by design — §7.2's cumulative stats need the full
/// history.
public struct RelationshipEvent: Codable, Equatable, Identifiable, Sendable {
    public enum EventType: String, Codable, Sendable {
        case becameTogether = "became_together"
        case becameApart = "became_apart"
    }

    public var id: String
    public var type: EventType
    public var timestamp: Date
    public var triggeredBy: String

    public init(id: String, type: EventType, timestamp: Date, triggeredBy: String) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.triggeredBy = triggeredBy
    }
}
