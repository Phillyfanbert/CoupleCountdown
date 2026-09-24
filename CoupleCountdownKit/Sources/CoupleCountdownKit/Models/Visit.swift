// Visit.swift — a planned time together, and how the main countdown follows the plan

import Foundation

/// Mirrors `couples/{coupleId}/visits/{id}`: a planned meetup with a real
/// time ("Oct 1, 6:30 PM", when the flight lands), so a couple can have
/// several coming up and see them on the calendar. `start` is a true instant
/// — unlike an anniversary, a meeting time means the same moment for both
/// partners, just shown in each one's local time.
public struct Visit: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var start: Date
    public var note: String?
    public var createdBy: String

    public init(id: String, start: Date, note: String?, createdBy: String) {
        self.id = id
        self.start = start
        self.note = note
        self.createdBy = createdBy
    }
}

/// How `RelationshipState.nextMeetupDate` — what the main countdown and the
/// widget count down to — follows the planned visits. Mirrored in
/// web/logic.js; keep the two in step.
public enum MeetupPlanner {
    /// The earliest visit that hasn't started yet.
    public static func nextUpcoming(_ visits: [Visit], now: Date = Date()) -> Visit? {
        visits.filter { $0.start > now }.min { $0.start < $1.start }
    }

    /// What `nextMeetupDate` should be after the visits change. A still-
    /// upcoming `current` that no visit accounts for (set before visits
    /// existed) is kept unless a planned visit comes sooner; if `removed`
    /// was the visit it pointed at, it moves on to the next one (or none).
    public static func resolvedNextMeetup(
        current: Date?,
        visits: [Visit],
        removed: Visit? = nil,
        now: Date = Date()
    ) -> Date? {
        var current = current
        if let removed, let c = current, abs(c.timeIntervalSince(removed.start)) < 1 {
            current = nil
        }
        let upcoming = nextUpcoming(visits, now: now)?.start
        guard let c = current, c > now else { return upcoming }
        guard let upcoming else { return c }
        return min(c, upcoming)
    }

    /// A picked date-and-time trimmed to the minute, so the same visit
    /// compares equal after a round trip through Firestore.
    public static func normalized(_ start: Date) -> Date {
        Date(timeIntervalSince1970: (start.timeIntervalSince1970 / 60).rounded(.down) * 60)
    }
}
