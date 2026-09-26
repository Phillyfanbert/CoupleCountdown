// CalendarDay.swift: a date-only value ("Aug 19") that means the same day in every time zone

import Foundation

/// A calendar day with no time of day: an anniversary, a birthday.
///
/// Storing such a day as an instant (e.g. local midnight) breaks for a
/// long-distance couple: Aug 19 00:00 in Tokyo is Aug 18 in Los Angeles, so
/// the partner to the west saw every date a day early. The convention both
/// clients use instead: store the day as **12:00 UTC** on that date, and read
/// it back with **UTC** components, never the reader's local ones. (Reading
/// UTC noon with local components would still be wrong at UTC+12 and beyond,
/// e.g. New Zealand in summer.) The web client mirrors this in web/logic.js.
public struct CalendarDay: Hashable, Comparable, Codable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day a date picker shows: its components in the user's calendar.
    public init(localDate: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: localDate)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// The day a stored Firestore value represents (see type docs).
    public init(stored: Date) {
        self.init(localDate: stored, calendar: Self.utc)
    }

    /// What to write to Firestore for this day: 12:00 UTC on it.
    public var storedDate: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }

    /// Midnight at the start of this day in `calendar`'s time zone, for
    /// display and day arithmetic in the reader's own calendar.
    public func localDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? storedDate
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
