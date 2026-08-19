// CountdownFormatter.swift — countdown/time zone display formatting shared by app & widget (DESIGN.md §6, §9.1)

import Foundation

public enum CountdownFormatter {
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
