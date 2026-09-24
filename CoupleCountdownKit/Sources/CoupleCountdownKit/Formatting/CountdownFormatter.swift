// CountdownFormatter.swift — countdown/time zone display formatting shared by app & widget (DESIGN.md §6, §9.1)

import Foundation

public enum CountdownFormatter {
    /// Whole calendar days from `from`'s day to `to`'s day in `calendar`
    /// (0 = same day), regardless of the times of day involved.
    public static func calendarDays(from: Date, to: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }

    /// "Today", "Tomorrow", "in 12 days", "Yesterday", "3 days ago" —
    /// matches relativeDayLabel in web/logic.js.
    public static func relativeDayLabel(_ days: Int) -> String {
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...: return "in \(days) days"
        default: return "\(-days) days ago"
        }
    }

    /// The date range to hand to SwiftUI's `Text(timerInterval:countsDown:)`
    /// — the OS handles the actual digit ticking from this, so this just
    /// needs to be a valid, stable interval (DESIGN.md §6).
    public static func timerInterval(to targetDate: Date, from now: Date = Date()) -> ClosedRange<Date> {
        let start = min(now, targetDate)
        let end = max(now, targetDate)
        return start...end
    }

    /// "Her: 9:14 PM CDT" style formatting for a partner's current local
    /// time (DESIGN.md §9.1) — display-only, doesn't touch how
    /// `nextMeetupDate` is stored or computed.
    public static func localTimeString(label: String, timeZoneIdentifier: String, now: Date = Date()) -> String {
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = timeZone

        let time = formatter.string(from: now)
        let abbreviation = timeZone.abbreviation(for: now) ?? ""
        return "\(label): \(time) \(abbreviation)".trimmingCharacters(in: .whitespaces)
    }
}
