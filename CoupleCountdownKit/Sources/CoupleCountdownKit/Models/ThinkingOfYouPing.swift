// ThinkingOfYouPing.swift — ephemeral "thinking of you" nudge model (DESIGN.md §5.1, §7.1)

import Foundation

/// Mirrors `couples/{coupleId}/pings/{pingId}` (DESIGN.md §5.1, §7.1).
/// Ephemeral by design — a Firestore TTL policy auto-expires these, and
/// they're never written into the permanent event log.
///
/// `expiresAt` is a separate field from `sentAt`, not a TTL policy applied
/// to `sentAt` directly — a TTL field must hold the *expiration* instant,
/// not the creation instant. Applying TTL straight to `sentAt` would make
/// every ping eligible for deletion the moment it's created (since
/// `now > sentAt` is true almost immediately), deleting pings within
/// about a day instead of after the intended few-day window. Caught while
/// actually configuring TTL against the real project, not by inspection.
public struct ThinkingOfYouPing: Codable, Equatable, Identifiable, Sendable {
    public static let lifetime: TimeInterval = 5 * 86_400 // a few days

    public var id: String
    public var sentBy: String
    public var sentAt: Date
    public var expiresAt: Date

    public init(id: String, sentBy: String, sentAt: Date, expiresAt: Date? = nil) {
        self.id = id
        self.sentBy = sentBy
        self.sentAt = sentAt
        self.expiresAt = expiresAt ?? sentAt.addingTimeInterval(Self.lifetime)
    }
}
