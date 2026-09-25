// CoupleCountdownKitTests.swift — unit tests for the pure-Foundation logic in this package.

import XCTest
@testable import CoupleCountdownKit

/// A gregorian calendar pinned to one time zone, so these tests mean the same
/// thing on any machine.
private func calendar(_ identifier: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: identifier)!
    return calendar
}

final class CalendarDayTests: XCTestCase {
    func testStoredDayReadsTheSameInEveryTimeZone() {
        // The bug this replaces: a date saved as local midnight in Tokyo read
        // as the previous day in Los Angeles.
        let picked = calendar("Asia/Tokyo").date(from: DateComponents(year: 2026, month: 8, day: 19))!
        let day = CalendarDay(localDate: picked, calendar: calendar("Asia/Tokyo"))
        let stored = day.storedDate

        XCTAssertEqual(CalendarDay(stored: stored), CalendarDay(year: 2026, month: 8, day: 19))
        for zone in ["America/Los_Angeles", "Europe/London", "Asia/Tokyo", "Pacific/Auckland", "Pacific/Kiritimati"] {
            let local = CalendarDay(stored: stored).localDate(calendar: calendar(zone))
            let c = calendar(zone).dateComponents([.year, .month, .day], from: local)
            XCTAssertEqual([c.year, c.month, c.day], [2026, 8, 19], "wrong day in \(zone)")
        }
    }
}

final class ImportantDateTests: XCTestCase {
    private let la = calendar("America/Los_Angeles")

    private func important(_ year: Int, _ month: Int, _ day: Int, repeats: Bool = true) -> ImportantDate {
        ImportantDate(id: "1", label: "Anniversary", date: CalendarDay(year: year, month: month, day: day).storedDate, repeatsAnnually: repeats, createdBy: "uidA")
    }

    func testNextOccurrenceReturnsSameYearWhenUpcoming() {
        let now = la.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let next = important(2020, 8, 19).nextOccurrence(now: now, calendar: la)
        let components = la.dateComponents([.year, .month, .day], from: next)
        XCTAssertEqual([components.year, components.month, components.day], [2026, 8, 19])
    }

    func testNextOccurrenceRollsForwardWhenAlreadyPassedThisYear() {
        let now = la.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let next = important(2020, 8, 19).nextOccurrence(now: now, calendar: la)
        let components = la.dateComponents([.year, .month, .day], from: next)
        XCTAssertEqual([components.year, components.month, components.day], [2027, 8, 19])
    }

    func testYearlyDateThatIsTodayIsTodayNotNextYear() {
        // Was rolled forward a year: the candidate (midnight) was compared
        // against the current instant, which is always later on the day.
        let now = la.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 15, minute: 30))!
        let date = important(2020, 8, 19)
        XCTAssertEqual(date.daysUntilNextOccurrence(now: now, calendar: la), 0)
        XCTAssertFalse(date.isPast(now: now, calendar: la))
    }

    func testNonRepeatingDateKeepsItsDayAndCanBePast() {
        let date = important(2019, 6, 1, repeats: false)
        let next = date.nextOccurrence(now: Date(), calendar: la)
        let components = la.dateComponents([.year, .month, .day], from: next)
        XCTAssertEqual([components.year, components.month, components.day], [2019, 6, 1])
        XCTAssertTrue(date.isPast(now: Date(), calendar: la))
        XCTAssertLessThan(date.daysUntilNextOccurrence(now: Date(), calendar: la), 0)
    }
}

final class MeetupPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func visit(_ id: String, hoursFromNow: Double) -> Visit {
        Visit(id: id, start: now.addingTimeInterval(hoursFromNow * 3600), note: nil, createdBy: "uidA")
    }

    func testNextUpcomingSkipsPastVisitsAndPicksTheEarliest() {
        let visits = [visit("past", hoursFromNow: -5), visit("later", hoursFromNow: 72), visit("soon", hoursFromNow: 10)]
        XCTAssertEqual(MeetupPlanner.nextUpcoming(visits, now: now)?.id, "soon")
        XCTAssertNil(MeetupPlanner.nextUpcoming([visit("past", hoursFromNow: -1)], now: now))
    }

    func testResolvedPicksTheSoonerOfCurrentAndPlanned() {
        let visits = [visit("a", hoursFromNow: 48)]
        // No date yet, or a date already passed: follow the plan.
        XCTAssertEqual(MeetupPlanner.resolvedNextMeetup(current: nil, visits: visits, now: now), visits[0].start)
        XCTAssertEqual(MeetupPlanner.resolvedNextMeetup(current: now.addingTimeInterval(-60), visits: visits, now: now), visits[0].start)
        // An earlier date set before visits existed is kept.
        let earlier = now.addingTimeInterval(3600)
        XCTAssertEqual(MeetupPlanner.resolvedNextMeetup(current: earlier, visits: visits, now: now), earlier)
    }

    func testRemovingTheCurrentVisitMovesOnToTheNextOrNone() {
        let a = visit("a", hoursFromNow: 24)
        let b = visit("b", hoursFromNow: 96)
        XCTAssertEqual(MeetupPlanner.resolvedNextMeetup(current: a.start, visits: [b], removed: a, now: now), b.start)
        XCTAssertNil(MeetupPlanner.resolvedNextMeetup(current: a.start, visits: [], removed: a, now: now))
        // Removing some other visit leaves the current one alone.
        XCTAssertEqual(MeetupPlanner.resolvedNextMeetup(current: a.start, visits: [a], removed: b, now: now), a.start)
    }

    func testNormalizedTrimsToTheMinute() {
        let start = Date(timeIntervalSince1970: 1_800_000_123.456)
        XCTAssertEqual(MeetupPlanner.normalized(start).timeIntervalSince1970, 1_800_000_120)
    }
}

final class RelativeDayTests: XCTestCase {
    func testLabels() {
        XCTAssertEqual(CountdownFormatter.relativeDayLabel(0), "Today")
        XCTAssertEqual(CountdownFormatter.relativeDayLabel(1), "Tomorrow")
        XCTAssertEqual(CountdownFormatter.relativeDayLabel(12), "in 12 days")
        XCTAssertEqual(CountdownFormatter.relativeDayLabel(-1), "Yesterday")
        XCTAssertEqual(CountdownFormatter.relativeDayLabel(-3), "3 days ago")
    }

    func testCalendarDaysIgnoresTimeOfDay() {
        let la = calendar("America/Los_Angeles")
        let lateTonight = la.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 23, minute: 50))!
        let earlyTomorrow = la.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 0, minute: 10))!
        XCTAssertEqual(CountdownFormatter.calendarDays(from: lateTonight, to: earlyTomorrow, calendar: la), 1)
    }
}

final class CumulativeStatsCalculatorTests: XCTestCase {
    func testEmptyEventsProduceZeroStats() {
        let stats = CumulativeStatsCalculator.calculate(events: [])
        XCTAssertEqual(stats.totalDaysTogether, 0)
        XCTAssertEqual(stats.totalDaysApart, 0)
    }

    func testSumsSpansBetweenConsecutiveEvents() {
        let day: TimeInterval = 86_400
        let start = Date(timeIntervalSince1970: 0)

        let events = [
            RelationshipEvent(id: "1", type: .becameTogether, timestamp: start, triggeredBy: "uidA"),
            RelationshipEvent(id: "2", type: .becameApart, timestamp: start.addingTimeInterval(5 * day), triggeredBy: "uidA"),
            RelationshipEvent(id: "3", type: .becameTogether, timestamp: start.addingTimeInterval(15 * day), triggeredBy: "uidB"),
        ]
        let now = start.addingTimeInterval(20 * day)

        let stats = CumulativeStatsCalculator.calculate(events: events, now: now)
        // together: [0,5) = 5 days, [15,20) = 5 days => 10 total
        // apart: [5,15) = 10 days
        XCTAssertEqual(stats.totalDaysTogether, 10, accuracy: 0.0001)
        XCTAssertEqual(stats.totalDaysApart, 10, accuracy: 0.0001)
    }
}

final class MilestoneCheckerTests: XCTestCase {
    func testCountdownReachedZeroWhenDatePassedAndApart() {
        let past = Date().addingTimeInterval(-60)
        XCTAssertTrue(MilestoneChecker.countdownReachedZero(nextMeetupDate: past, status: .apart))
    }

    func testCountdownNotReachedZeroWhenDateInFuture() {
        let future = Date().addingTimeInterval(60)
        XCTAssertFalse(MilestoneChecker.countdownReachedZero(nextMeetupDate: future, status: .apart))
    }

    func testCountdownReachedZeroFalseWhenAlreadyTogether() {
        let past = Date().addingTimeInterval(-60)
        XCTAssertFalse(MilestoneChecker.countdownReachedZero(nextMeetupDate: past, status: .together))
    }

    func testCountdownReachedZeroFalseWhenNoDateSet() {
        XCTAssertFalse(MilestoneChecker.countdownReachedZero(nextMeetupDate: nil, status: .apart))
    }

    func testRoundDayMilestoneReachedPicksLargestQualifying() {
        XCTAssertEqual(MilestoneChecker.roundDayMilestoneReached(totalDaysTogether: 150), 100)
        XCTAssertEqual(MilestoneChecker.roundDayMilestoneReached(totalDaysTogether: 6.9), nil)
        XCTAssertEqual(MilestoneChecker.roundDayMilestoneReached(totalDaysTogether: 1200), 1000)
    }
}

final class AppGroupCacheTests: XCTestCase {
    func testWriteThenReadRoundTrips() {
        // A suite name with no real App Group entitlement still works for
        // UserDefaults(suiteName:) in a unit-test/CLI context — it just
        // isn't actually shared with another process, which is fine here.
        let cache = AppGroupCache(suiteName: "group.test.couplecountdown")
        let state = RelationshipState(
            status: .together,
            nextMeetupDate: Date(timeIntervalSince1970: 1_700_000_000),
            participantUIDs: ["uidA", "uidB"],
            partnerProfiles: [
                "uidA": PartnerProfile(displayName: "A", timeZoneIdentifier: "America/Chicago")
            ],
            lastUpdatedBy: "uidA",
            lastUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        cache.write(state)
        let readBack = cache.read()
        XCTAssertEqual(readBack, state)

        let ping = ThinkingOfYouPing(id: "p1", sentBy: "uidB", sentAt: Date(timeIntervalSince1970: 1_700_000_200))
        cache.writeUnseenPing(ping)
        XCTAssertEqual(cache.readUnseenPing(), ping)
        cache.writeUnseenPing(nil)
        XCTAssertNil(cache.readUnseenPing())

        // Sign-out / leaving a pairing must stop the widget showing it.
        cache.writeUnseenPing(ping)
        cache.clear()
        XCTAssertNil(cache.read())
        XCTAssertNil(cache.readUnseenPing())
    }
}

final class ThinkingOfYouPingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func ping(_ id: String, from sender: String, hoursAgo: Double, seen: Bool = false) -> ThinkingOfYouPing {
        ThinkingOfYouPing(id: id, sentBy: sender, sentAt: now.addingTimeInterval(-hoursAgo * 3600), seenAt: seen ? now : nil)
    }

    func testUnseenKeepsOnlyThePartnersRecentUndismissedPingsNewestFirst() {
        let pings = [
            ping("mine", from: "me", hoursAgo: 1),
            ping("older", from: "partner", hoursAgo: 30),
            ping("newest", from: "partner", hoursAgo: 2),
            ping("dismissed", from: "partner", hoursAgo: 3, seen: true),
            ping("stale", from: "partner", hoursAgo: 24 * 6),
        ]
        XCTAssertEqual(ThinkingOfYouPing.unseen(pings, for: "me", now: now).map(\.id), ["newest", "older"])
        XCTAssertEqual(ThinkingOfYouPing.unseen(pings, for: "partner", now: now).map(\.id), ["mine"])
    }

    func testHeadline() {
        XCTAssertEqual(ThinkingOfYouPing.headline(senderName: "Sam", count: 1), "Sam is thinking of you")
        XCTAssertEqual(ThinkingOfYouPing.headline(senderName: "Sam", count: 3), "Sam thought of you 3 times")
        XCTAssertEqual(ThinkingOfYouPing.headline(senderName: nil, count: 1), "Your partner is thinking of you")
    }
}

/// Shapes copied from real Firestore REST responses for this project.
final class FirestoreRESTTests: XCTestCase {
    func testTimestampsWithAndWithoutFractionalSeconds() {
        let base = Date(timeIntervalSince1970: 1_790_294_669) // 2026-09-25T00:04:29Z
        XCTAssertEqual(FirestoreREST.timestamp("2026-09-25T00:04:29Z"), base)
        XCTAssertEqual(FirestoreREST.timestamp("2026-09-25T00:04:29.519Z")!.timeIntervalSince(base), 0.519, accuracy: 1e-6)
        XCTAssertEqual(FirestoreREST.timestamp("2026-09-25T00:04:29.209719Z")!.timeIntervalSince(base), 0.209719, accuracy: 1e-6)
        XCTAssertEqual(FirestoreREST.timestamp("2026-09-25T09:04:29.5+09:00")!.timeIntervalSince(base), 0.5, accuracy: 1e-6)
        XCTAssertNil(FirestoreREST.timestamp("not a date"))
    }

    func testCoupleDocumentDecodes() throws {
        let json = """
        {"name": "projects/p/databases/(default)/documents/couples/LY6RAA", "fields": {
          "status": {"stringValue": "apart"},
          "nextMeetupDate": {"timestampValue": "2026-10-01T23:30:00Z"},
          "participantUIDs": {"arrayValue": {"values": [{"stringValue": "uidA"}, {"stringValue": "uidB"}]}},
          "partnerProfiles": {"mapValue": {"fields": {"uidA": {"mapValue": {"fields": {
            "displayName": {"stringValue": "Alex"}, "timeZoneIdentifier": {"stringValue": "America/Chicago"}}}}}}},
          "lastUpdatedBy": {"stringValue": "uidA"},
          "lastUpdatedAt": {"timestampValue": "2026-09-25T00:04:29.519Z"}
        }}
        """
        let state = try XCTUnwrap(FirestoreREST.relationshipState(fromDocument: Data(json.utf8)))
        XCTAssertEqual(state.status, .apart)
        XCTAssertEqual(state.participantUIDs, ["uidA", "uidB"])
        XCTAssertEqual(state.partnerProfiles["uidA"]?.displayName, "Alex")
        XCTAssertEqual(state.nextMeetupDate, FirestoreREST.timestamp("2026-10-01T23:30:00Z"))
    }

    func testRunQueryPingsDecode() throws {
        let json = """
        [{"document": {"name": "projects/p/databases/(default)/documents/couples/LY6RAA/pings/mVr02uplPHGW8zL6MmzO",
           "fields": {"sentBy": {"stringValue": "uidB"},
                      "expiresAt": {"timestampValue": "2026-09-30T00:04:30.150Z"},
                      "sentAt": {"timestampValue": "2026-09-25T00:04:30.199Z"}},
           "createTime": "2026-09-25T00:04:30.209719Z", "updateTime": "2026-09-25T00:04:30.209719Z"},
          "readTime": "2026-09-25T00:04:30.443833Z"},
         {"document": {"name": "projects/p/databases/(default)/documents/couples/LY6RAA/pings/seen1",
           "fields": {"sentBy": {"stringValue": "uidB"},
                      "sentAt": {"timestampValue": "2026-09-24T20:00:00Z"},
                      "seenAt": {"timestampValue": "2026-09-24T21:00:00.5Z"}}},
          "readTime": "2026-09-25T00:04:30.443833Z"}]
        """
        let pings = try XCTUnwrap(FirestoreREST.pings(fromRunQuery: Data(json.utf8)))
        XCTAssertEqual(pings.map(\.id), ["mVr02uplPHGW8zL6MmzO", "seen1"])
        XCTAssertEqual(pings[0].sentBy, "uidB")
        XCTAssertNil(pings[0].seenAt)
        XCTAssertNotNil(pings[1].seenAt)

        // No matches: rows with only a readTime.
        XCTAssertEqual(FirestoreREST.pings(fromRunQuery: Data(#"[{"readTime": "2026-09-25T00:04:30Z"}]"#.utf8)), [])
        // An error body isn't a runQuery result.
        XCTAssertNil(FirestoreREST.pings(fromRunQuery: Data(#"{"error": {"code": 403}}"#.utf8)))
    }

    func testRecentPingsQueryShape() throws {
        let body = FirestoreREST.recentPingsQuery(since: Date(timeIntervalSince1970: 1_790_294_669))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let query = try XCTUnwrap(json["structuredQuery"] as? [String: Any])
        let filter = try XCTUnwrap((query["where"] as? [String: Any])?["fieldFilter"] as? [String: Any])
        XCTAssertEqual(filter["op"] as? String, "GREATER_THAN")
        XCTAssertEqual((filter["value"] as? [String: Any])?["timestampValue"] as? String, "2026-09-25T00:04:29Z")
    }
}
