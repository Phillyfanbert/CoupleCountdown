// PartnerProfile.swift — per-partner display name & time zone model (DESIGN.md §5.1, §9.1)

import Foundation

public struct PartnerProfile: Codable, Equatable, Sendable {
    /// Longest name either client accepts (the web's inputs use the same).
    /// The rules refuse names over 60 characters, and the iPhone used to
    /// have no limit: a long name created the account, then failed to save
    /// it with a misleading "couldn't sign in".
    public static let maxNameLength = 30

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
