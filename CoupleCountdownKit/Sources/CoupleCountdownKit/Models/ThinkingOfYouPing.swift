// ThinkingOfYouPing.swift — ephemeral "thinking of you" nudge model (DESIGN.md §5.1, §7.1)

import Foundation

/// Mirrors `couples/{coupleId}/pings/{pingId}` (DESIGN.md §5.1, §7.1).
/// Ephemeral by design — a Firestore TTL policy auto-expires these after
/// a few days, and they're never written into the permanent event log.
public struct ThinkingOfYouPing: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var sentBy: String
    public var sentAt: Date

    public init(id: String, sentBy: String, sentAt: Date) {
        self.id = id
        self.sentBy = sentBy
        self.sentAt = sentAt
    }
}
