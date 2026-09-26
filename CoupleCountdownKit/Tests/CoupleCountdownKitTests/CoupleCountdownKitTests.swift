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

final class CountdownPartsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testSplitsIntoDaysHoursMinutesSecondsAndStopsAtZero() {
        // Same case as countdownParts in web/logic.test.js.
        let target = start.addingTimeInterval(2 * 86_400 + 3 * 3_600 + 4 * 60 + 5)
        XCTAssertEqual(CountdownFormatter.parts(until: target, from: start), .init(days: 2, hours: 3, minutes: 4, seconds: 5))
        XCTAssertEqual(CountdownFormatter.parts(until: target, from: start.addingTimeInterval(0.4)), .init(days: 2, hours: 3, minutes: 4, seconds: 4))
        XCTAssertNil(CountdownFormatter.parts(until: start, from: start))
        XCTAssertNil(CountdownFormatter.parts(until: start, from: target))
    }

    func testWidgetDayCountsWholeDaysAndEndsTheTimerAtTheNextBoundary() {
        let target = start.addingTimeInterval(2 * 86_400 + 3 * 3_600)
        let now = CountdownFormatter.widgetDay(until: target, from: start)
        XCTAssertEqual(now?.days, 2)
        XCTAssertEqual(now?.dayEnds, start.addingTimeInterval(3 * 3_600))
        // Exactly on a boundary, a full day of timer is left, not 0:00.
        let onBoundary = CountdownFormatter.widgetDay(until: target, from: target.addingTimeInterval(-86_400))
        XCTAssertEqual(onBoundary?.days, 0)
        XCTAssertEqual(onBoundary?.dayEnds, target)
        XCTAssertNil(CountdownFormatter.widgetDay(until: target, from: target))
    }

    func testWidgetTimelineHasAnEntryEachTimeTheDayCountDrops() {
        let target = start.addingTimeInterval(2 * 86_400 + 3 * 3_600)
        XCTAssertEqual(CountdownFormatter.widgetTimelineDates(until: target, from: start), [
            start,
            start.addingTimeInterval(3 * 3_600),
            start.addingTimeInterval(86_400 + 3 * 3_600),
            target,
        ])
        XCTAssertEqual(CountdownFormatter.widgetTimelineDates(until: target, from: start, limit: 2).count, 2)
        XCTAssertEqual(CountdownFormatter.widgetTimelineDates(until: start, from: target), [target])
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

final class SeparationTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Double) -> Date { t0.addingTimeInterval(n * 86_400) }
    private func event(_ type: RelationshipEvent.EventType, _ at: Date) -> RelationshipEvent {
        RelationshipEvent(id: UUID().uuidString, type: type, timestamp: at, triggeredBy: "a")
    }

    func testPairingStartsTheFirstStretchApart() {
        // Paired while apart, first met on day 44: those 44 days are apart.
        let events = [event(.becameTogether, day(44))]
        let stats = CumulativeStatsCalculator.calculate(events: events, pairedAt: t0, now: day(50))
        XCTAssertEqual(stats.totalDaysApart, 44, accuracy: 1e-6)
        XCTAssertEqual(stats.totalDaysTogether, 6, accuracy: 1e-6)
        // Without the pairing time (older pairings) it's the old behavior.
        XCTAssertEqual(CumulativeStatsCalculator.calculate(events: events, now: day(50)).totalDaysApart, 0)
    }

    func testFreshPairingIsApartSoFar() {
        let stats = CumulativeStatsCalculator.calculate(events: [], pairedAt: t0, now: day(3))
        XCTAssertEqual(stats.totalDaysApart, 3, accuracy: 1e-6)
        XCTAssertEqual(CumulativeStatsCalculator.separations(events: [], pairedAt: t0), [Separation(start: t0, end: nil)])
    }

    func testSeparationsRunFromPartingToReunionAndIgnoreRepeats() {
        let events = [
            event(.becameTogether, day(44)),
            event(.becameTogether, day(44.001)), // both tapped
            event(.becameApart, day(50)),
            event(.becameApart, day(50.001)),
            event(.becameTogether, day(80)),
            event(.becameApart, day(85)),
        ]
        let separations = CumulativeStatsCalculator.separations(events: events, pairedAt: t0)
        XCTAssertEqual(separations, [
            Separation(start: t0, end: day(44)),
            Separation(start: day(50), end: day(80)),
            Separation(start: day(85), end: nil),
        ])
        XCTAssertEqual(separations[1].duration(), 30 * 86_400, accuracy: 1e-6)
        XCTAssertEqual(separations[2].duration(now: day(90)), 5 * 86_400, accuracy: 1e-6)
    }

    func testDurationLabelsStatDaysAndReunionMessages() {
        XCTAssertEqual(CountdownFormatter.durationLabel(20), "less than a minute")
        XCTAssertEqual(CountdownFormatter.durationLabel(60), "1 minute")
        XCTAssertEqual(CountdownFormatter.durationLabel(5 * 3_600), "5 hours")
        XCTAssertEqual(CountdownFormatter.durationLabel(86_400 + 5 * 3_600), "1 day, 5 hours")
        XCTAssertEqual(CountdownFormatter.durationLabel(2 * 86_400), "2 days")
        XCTAssertEqual(CountdownFormatter.durationLabel(44.5 * 86_400), "44 days")
        XCTAssertEqual(CountdownFormatter.statDays(0.83), "0.8")
        XCTAssertEqual(CountdownFormatter.statDays(23.6), "24")
        XCTAssertEqual(CountdownFormatter.reunionMessage(apartFor: 44 * 86_400), "Congratulations! You're together again after 44 days apart 💞")
        XCTAssertEqual(CountdownFormatter.reunionMessage(apartFor: 30), "Congratulations! You're together again 💞")
        XCTAssertEqual(CountdownFormatter.reunionMessage(partnerName: "Sam", apartFor: 2 * 86_400), "Sam says you're together after 2 days apart! Congratulations 💞")
        XCTAssertEqual(CountdownFormatter.reunionMessage(partnerName: "Sam", apartFor: nil), "Sam says you're together! Congratulations 💞")
    }
}

final class JoinLinkTests: XCTestCase {
    func testInviteLinkOpensTheWebAppWithTheCodeFilledIn() {
        // web/app.js reads ?join= to prefill the Join screen.
        XCTAssertEqual(JoinLink.url(for: "ABC234").absoluteString, "https://couplecountdown-7715c.web.app/?join=ABC234")
    }
}

final class VisitTimingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMeetingEarlyFindsTheVisitThatWasCountedDownTo() {
        let planned = Visit(id: "v", start: now.addingTimeInterval(86_400), note: nil, createdBy: "a")
        let later = Visit(id: "w", start: now.addingTimeInterval(30 * 86_400), note: nil, createdBy: "a")
        XCTAssertEqual(MeetupPlanner.visitMetEarly(current: planned.start, visits: [later, planned], now: now)?.id, "v")
        // On time or late: nothing to move.
        XCTAssertNil(MeetupPlanner.visitMetEarly(current: now.addingTimeInterval(-60), visits: [planned], now: now))
        // A week out is a separate trip: seeing each other now doesn't cancel it.
        let nextWeek = Visit(id: "n", start: now.addingTimeInterval(7 * 86_400), note: nil, createdBy: "a")
        XCTAssertNil(MeetupPlanner.visitMetEarly(current: nextWeek.start, visits: [nextWeek], now: now))
        XCTAssertNil(MeetupPlanner.visitMetEarly(current: nil, visits: [planned], now: now))
    }

    func testSameWallTimeInAnotherZone() {
        // 6:30 PM on Oct 1 in Chicago (CDT, UTC-5) = 23:30Z; the same wall
        // time in Tokyo (UTC+9) = 09:30Z.
        let chicago = TimeZone(identifier: "America/Chicago")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let inChicago = Date(timeIntervalSince1970: 1_790_897_400) // 2026-10-01T23:30:00Z
        let inTokyo = MeetupPlanner.sameWallTime(inChicago, from: chicago, to: tokyo)
        XCTAssertEqual(inTokyo.timeIntervalSince1970, 1_790_847_000) // 2026-10-01T09:30:00Z
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
