// ImportantDate.swift — anniversary/important-date countdown model (DESIGN.md §5.1, §7.4)

import Foundation

/// Mirrors `couples/{coupleId}/importantDates/{id}` (DESIGN.md §5.1, §7.4).
/// Deliberately separate from `RelationshipState` — these are
/// informational countdowns, not tied to the apart/together state
/// machine (§8).
public struct ImportantDate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
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

    /// The next occurrence to count down to. If `repeatsAnnually` and this
    /// year's date has already passed, rolls forward to next year rather
    /// than counting into negative days (DESIGN.md §7.4).
    public func nextOccurrence(now: Date = Date(), calendar: Calendar = .current) -> Date {
        guard repeatsAnnually else { return date }

        let monthDay = calendar.dateComponents([.month, .day], from: date)
        var candidateComponents = calendar.dateComponents([.year, .month, .day], from: now)
        candidateComponents.month = monthDay.month
        candidateComponents.day = monthDay.day

        guard let candidate = calendar.date(from: candidateComponents) else { return date }
        if candidate >= now {
            return candidate
        }
        return calendar.date(byAdding: .year, value: 1, to: candidate) ?? candidate
    }
}
