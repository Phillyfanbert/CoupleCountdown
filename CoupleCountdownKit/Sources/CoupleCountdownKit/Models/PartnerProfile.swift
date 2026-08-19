// PartnerProfile.swift — per-partner display name & time zone model (DESIGN.md §5.1, §9.1)

import Foundation

public struct PartnerProfile: Codable, Equatable, Sendable {
    public var displayName: String
    public var timeZoneIdentifier: String

    public init(displayName: String, timeZoneIdentifier: String) {
        self.displayName = displayName
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}
