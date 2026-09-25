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

    /// Whole days, hours, minutes, and seconds left — what the countdown
    /// shows. Mirrors countdownParts in web/logic.js.
    public struct Parts: Equatable, Sendable {
        public var days: Int
        public var hours: Int
        public var minutes: Int
        public var seconds: Int
    }

    /// Time left until `target`, or nil once it has arrived.
    public static func parts(until target: Date, from now: Date = Date()) -> Parts? {
        let remaining = target.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        let total = Int(remaining.rounded(.down))
        return Parts(days: total / 86_400, hours: total % 86_400 / 3_600, minutes: total % 3_600 / 60, seconds: total % 60)
    }

    /// For the widget, which can't redraw every second: the whole days left
    /// (drawn as text) and when the current partial day runs out (the end of
    /// a live `Text(timerInterval:)` showing the hours, minutes, and seconds).
    /// Exactly on a day boundary the new day counts as partial, so the timer
    /// runs a full 24 hours instead of sitting at 0:00 — a half-second
    /// tolerance keeps floating-point noise from tipping that the wrong way.
    public static func widgetDay(until target: Date, from now: Date) -> (days: Int, dayEnds: Date)? {
        let remaining = target.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        let days = max(0, Int(((remaining - 0.5) / 86_400).rounded(.up)) - 1)
        return (days, target.addingTimeInterval(-Double(days) * 86_400))
    }

    /// When the widget's timeline needs an entry: now, each moment the day
    /// count drops, and the target itself (where it switches to asking
    /// whether they've met). Capped at `limit` entries; the widget reloads
    /// long before it runs out.
    public static func widgetTimelineDates(until target: Date, from now: Date, limit: Int = 32) -> [Date] {
        var dates = [now]
        var cursor = now
        while dates.count < limit, let day = widgetDay(until: target, from: cursor) {
            cursor = day.dayEnds
            dates.append(cursor)
        }
        return dates
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
