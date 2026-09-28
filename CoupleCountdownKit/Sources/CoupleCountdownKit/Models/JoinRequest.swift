// JoinRequest.swift: someone asking to join a pairing, waiting for the creator's approval (DESIGN.md §5.3)

import Foundation

/// Mirrors `couples/{coupleId}.joinRequest`. The person with the code asks,
/// in their own name; the creator sees "Sam Lee wants to pair with you" and
/// approves (which adds them) or declines (which clears this).
public struct JoinRequest: Codable, Equatable, Sendable {
    public var uid: String
    public var displayName: String
    public var lastName: String?
    public var timeZoneIdentifier: String
    public var requestedAt: Date?

    public init(uid: String, displayName: String, lastName: String?, timeZoneIdentifier: String, requestedAt: Date? = nil) {
        self.uid = uid
        self.displayName = displayName
        self.lastName = lastName
        self.timeZoneIdentifier = timeZoneIdentifier
        self.requestedAt = requestedAt
    }

    /// "Sam Lee": what the creator is asked to approve.
    public var fullName: String {
        PartnerProfile.fullName(first: displayName, last: lastName)
    }

    /// Their entry on the couple doc once approved.
    public var profile: PartnerProfile {
        PartnerProfile(displayName: displayName, lastName: lastName, timeZoneIdentifier: timeZoneIdentifier)
    }
}
