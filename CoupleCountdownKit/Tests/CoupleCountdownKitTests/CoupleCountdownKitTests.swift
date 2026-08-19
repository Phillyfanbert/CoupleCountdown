// CoupleCountdownKitTests.swift — unit tests for the pure-Foundation logic in this package.

import XCTest
@testable import CoupleCountdownKit

final class ImportantDateTests: XCTestCase {
    func testNextOccurrenceReturnsSameYearWhenUpcoming() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let anniversary = calendar.date(from: DateComponents(year: 2020, month: 8, day: 19))!
        let date = ImportantDate(id: "1", label: "Anniversary", date: anniversary, repeatsAnnually: true, createdBy: "uidA")

        let next = date.nextOccurrence(now: now, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day], from: next)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 19)
    }

    func testNextOccurrenceRollsForwardWhenAlreadyPassedThisYear() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let anniversary = calendar.date(from: DateComponents(year: 2020, month: 8, day: 19))!
        let date = ImportantDate(id: "1", label: "Anniversary", date: anniversary, repeatsAnnually: true, createdBy: "uidA")

        let next = date.nextOccurrence(now: now, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day], from: next)
        XCTAssertEqual(components.year, 2027)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 19)
    }

    func testNonRepeatingDateIsReturnedAsIs() {
        let calendar = Calendar(identifier: .gregorian)
        let weddingDate = calendar.date(from: DateComponents(year: 2019, month: 6, day: 1))!
        let date = ImportantDate(id: "2", label: "Wedding", date: weddingDate, repeatsAnnually: false, createdBy: "uidA")

        XCTAssertEqual(date.nextOccurrence(now: Date(), calendar: calendar), weddingDate)
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
    }
}
