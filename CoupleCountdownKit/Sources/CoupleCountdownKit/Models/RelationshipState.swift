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

    public init(
        status: Status,
        nextMeetupDate: Date?,
        participantUIDs: [String],
        partnerProfiles: [String: PartnerProfile],
        lastUpdatedBy: String,
        lastUpdatedAt: Date
    ) {
        self.status = status
        self.nextMeetupDate = nextMeetupDate
        self.participantUIDs = participantUIDs
        self.partnerProfiles = partnerProfiles
        self.lastUpdatedBy = lastUpdatedBy
        self.lastUpdatedAt = lastUpdatedAt
    }
}
