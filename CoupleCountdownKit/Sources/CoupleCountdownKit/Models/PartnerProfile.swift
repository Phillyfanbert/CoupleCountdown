// PartnerProfile.swift: per-partner display name & time zone model (DESIGN.md §5.1, §9.1)

import Foundation

public struct PartnerProfile: Codable, Equatable, Sendable {
    /// Longest name either client accepts (the web's inputs use the same).
    /// The rules refuse names over 60 characters, and the iPhone used to
    /// have no limit: a long name created the account, then failed to save
    /// it with a misleading "couldn't sign in".
    public static let maxNameLength = 30

    /// First name: what the app calls them ("Sam is thinking of you").
    public var displayName: String
    /// Shown with the first name when the partner confirms a pairing
    /// ("Pair with Sam Lee?"), so they know it's the right person. Nil for
    /// accounts made before it was asked for.
    public var lastName: String?
    public var timeZoneIdentifier: String

    public init(displayName: String, lastName: String? = nil, timeZoneIdentifier: String) {
        self.displayName = displayName
        self.lastName = lastName
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    /// "Sam Lee", or just "Sam" without a last name.
    public var fullName: String {
        Self.fullName(first: displayName, last: lastName)
    }

    public static func fullName(first: String, last: String?) -> String {
        [first, last ?? ""]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }
}
