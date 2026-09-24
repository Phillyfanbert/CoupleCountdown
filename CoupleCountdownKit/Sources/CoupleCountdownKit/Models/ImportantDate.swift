// ImportantDate.swift — anniversary/important-date countdown model (DESIGN.md §5.1, §7.4)

import Foundation

/// Mirrors `couples/{coupleId}/importantDates/{id}` (DESIGN.md §5.1, §7.4).
/// Deliberately separate from `RelationshipState` — these are
/// informational countdowns, not tied to the apart/together state
/// machine (§8).
public struct ImportantDate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    /// The stored Firestore value: 12:00 UTC on the day (see `CalendarDay`).
    /// Use `day` rather than reading this with local components.
    public var date: Date
    public var repeatsAnnually: Bool
    public var createdBy: String

    public init(id: String, label: String, date: Date, repeatsAnnually: Bool, createdBy: String) {
        self.id = id
        self.label = label
        self.date = date
        self.repeatsAnnually = repeatsAnnually
        self.createdBy = createdBy
    }

    /// The calendar day this date is on — the same for both partners,
    /// whatever their time zones.
    public var day: CalendarDay {
        CalendarDay(stored: date)
    }

    /// The next occurrence to count down to, as local midnight of that day.
    /// A yearly date rolls forward to next year only once its day has fully
    /// passed — on the day itself it's "today", not 365 days away (compared
    /// against the start of today, not the current instant). A one-off date
    /// is returned as-is, even if past.
    public func nextOccurrence(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let day = self.day
        guard repeatsAnnually else { return day.localDate(calendar: calendar) }

        let today = calendar.startOfDay(for: now)
        let thisYear = calendar.component(.year, from: today)
        for year in [thisYear, thisYear + 1] {
            // Feb 29 in a non-leap year resolves to Mar 1, which is fine.
            if let candidate = calendar.date(from: DateComponents(year: year, month: day.month, day: day.day)),
               candidate >= today {
                return candidate
            }
        }
        return day.localDate(calendar: calendar)
    }

    /// Whole days from today to the next occurrence: 0 is today, negative
    /// only for a one-off date that has passed.
    public func daysUntilNextOccurrence(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: today, to: nextOccurrence(now: now, calendar: calendar)).day ?? 0
    }

    /// A one-off date whose day is behind us (yearly dates never are).
    public func isPast(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        !repeatsAnnually && daysUntilNextOccurrence(now: now, calendar: calendar) < 0
    }
}
