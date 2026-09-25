// ThinkingOfYouPing.swift — "thinking of you" nudge model and who-sees-what logic (DESIGN.md §5.1, §7.1)

import Foundation

/// Mirrors `couples/{coupleId}/pings/{pingId}` (DESIGN.md §5.1, §7.1).
/// Never written into the permanent event log — a nudge isn't a milestone.
///
/// `expiresAt` is a separate field from `sentAt`, not a TTL policy applied
/// to `sentAt` directly — a TTL field must hold the *expiration* instant,
/// not the creation instant. Applying TTL straight to `sentAt` would make
/// every ping eligible for deletion the moment it's created. (No TTL
/// policy is configured on the project yet; the field is there for one.)
public struct ThinkingOfYouPing: Codable, Equatable, Identifiable, Sendable {
    /// How long a ping stays worth showing to the partner.
    public static let lifetime: TimeInterval = 5 * 86_400 // a few days

    public var id: String
    public var sentBy: String
    public var sentAt: Date
    public var expiresAt: Date
    /// Set when the recipient dismisses it (or sends one back), on any of
    /// their devices — so all of them stop showing it.
    public var seenAt: Date?

    public init(id: String, sentBy: String, sentAt: Date, expiresAt: Date? = nil, seenAt: Date? = nil) {
        self.id = id
        self.sentBy = sentBy
        self.sentAt = sentAt
        self.expiresAt = expiresAt ?? sentAt.addingTimeInterval(Self.lifetime)
        self.seenAt = seenAt
    }

    /// The pings `uid` should be shown: sent by the partner, not yet
    /// dismissed, and recent. Newest first. Both clients and the widget
    /// use this, so they always agree on what's waiting.
    public static func unseen(_ pings: [ThinkingOfYouPing], for uid: String, now: Date = Date()) -> [ThinkingOfYouPing] {
        pings
            .filter { $0.sentBy != uid && $0.seenAt == nil && now.timeIntervalSince($0.sentAt) < lifetime }
            .sorted { $0.sentAt > $1.sentAt }
    }

    /// "Sam is thinking of you" / "Sam thought of you 3 times".
    public static func headline(senderName: String?, count: Int) -> String {
        let name = senderName?.isEmpty == false ? senderName! : "Your partner"
        return count > 1 ? "\(name) thought of you \(count) times" : "\(name) is thinking of you"
    }
}
