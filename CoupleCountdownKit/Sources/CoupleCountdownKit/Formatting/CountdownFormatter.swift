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

    /// How long a stretch apart has lasted: "3 days", "1 day, 5 hours",
    /// "5 hours", "12 minutes", "less than a minute". Mirrors durationLabel
    /// in web/logic.js.
    public static func durationLabel(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        let days = minutes / 1_440, hours = minutes % 1_440 / 60, mins = minutes % 60
        func count(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        if days >= 3 { return count(days, "day") }
        if days >= 1 { return hours > 0 ? "\(count(days, "day")), \(count(hours, "hour"))" : count(days, "day") }
        if hours >= 1 { return count(hours, "hour") }
        if mins >= 1 { return count(mins, "minute") }
        return "less than a minute"
    }

    /// A stats figure in days, the same on both clients: one decimal under
    /// 10 ("0.8"), whole days from there ("23"). The iPhone used to round to
    /// whole days, so the first day read as 0 while the web showed 0.8.
    public static func statDays(_ days: Double) -> String {
        days < 10 ? String(format: "%.1f", days) : String(Int(days.rounded()))
    }

    /// The reunion congratulations, with how long they were apart when that's
    /// known and worth saying (an hour or more). `partnerName` is set when the
    /// partner is the one who said so. Mirrors reunionMessage in web/logic.js.
    public static func reunionMessage(partnerName: String? = nil, apartFor: TimeInterval?) -> String {
        let after = apartFor.flatMap { $0 >= 3_600 ? " after \(durationLabel($0)) apart" : nil } ?? ""
        if let partnerName {
            return after.isEmpty
                ? "\(partnerName) says you're together! Congratulations 💞"
                : "\(partnerName) says you're together\(after)! Congratulations 💞"
        }
        return "Congratulations! You're together again\(after) 💞"
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
