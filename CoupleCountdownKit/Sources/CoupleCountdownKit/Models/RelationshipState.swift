// RelationshipState.swift — the shared couple document model (DESIGN.md §5.1)

import Foundation

/// Mirrors `couples/{coupleId}` (DESIGN.md §5.1). Deliberately a plain
/// Foundation type with no Firebase import — Firestore-specific code
/// (Timestamp bridging, FieldValue writes) stays in the app target's
/// FirestoreService per §5.6, so this type is usable from the widget
/// target too without pulling in the Firebase SDK.
public struct RelationshipState: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case apart
        case together
    }

    public var status: Status
    public var nextMeetupDate: Date?
    public var participantUIDs: [String]
    public var partnerProfiles: [String: PartnerProfile]
    public var lastUpdatedBy: String
    public var lastUpdatedAt: Date
    /// When the pairing was created. Pairings start apart, so this is where
    /// the first stretch apart begins — before any together/apart event
    /// exists. Nil for pairings made before it was recorded.
    public var pairedAt: Date?

    public init(
        status: Status,
        nextMeetupDate: Date?,
        participantUIDs: [String],
        partnerProfiles: [String: PartnerProfile],
        lastUpdatedBy: String,
        lastUpdatedAt: Date,
        pairedAt: Date? = nil
    ) {
        self.status = status
        self.nextMeetupDate = nextMeetupDate
        self.participantUIDs = participantUIDs
        self.partnerProfiles = partnerProfiles
        self.lastUpdatedBy = lastUpdatedBy
        self.lastUpdatedAt = lastUpdatedAt
        self.pairedAt = pairedAt
    }
}
