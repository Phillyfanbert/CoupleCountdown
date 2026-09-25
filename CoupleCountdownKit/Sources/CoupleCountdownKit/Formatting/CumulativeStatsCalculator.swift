// CumulativeStatsCalculator.swift — time together and apart, from the event log (DESIGN.md §7.2)

import Foundation

public struct CumulativeStats: Equatable, Sendable {
    public var totalDaysTogether: Double
    public var totalDaysApart: Double

    public init(totalDaysTogether: Double, totalDaysApart: Double) {
        self.totalDaysTogether = totalDaysTogether
        self.totalDaysApart = totalDaysApart
    }
}

/// One stretch apart: from parting (or pairing) until being together again.
public struct Separation: Equatable, Sendable {
    public var start: Date
    /// Nil while still apart.
    public var end: Date?

    public init(start: Date, end: Date?) {
        self.start = start
        self.end = end
    }

    public func duration(now: Date = Date()) -> TimeInterval {
        (end ?? now).timeIntervalSince(start)
    }
}

public enum CumulativeStatsCalculator {
    /// Walks the append-only event log and sums the duration of each
    /// together/apart span (DESIGN.md §7.2) — derived, not stored. The
    /// final span (from the last event to `now`) counts toward whichever
    /// status it currently reflects, since the couple hasn't toggled
    /// since then.
    ///
    /// `pairedAt` starts the first span: pairings begin apart, but no event
    /// marks that, so the whole first separation used to be missing.
    public static func calculate(events: [RelationshipEvent], pairedAt: Date? = nil, now: Date = Date()) -> CumulativeStats {
        let sorted = timeline(events, pairedAt: pairedAt)
        var togetherSeconds: TimeInterval = 0
        var apartSeconds: TimeInterval = 0

        for (index, event) in sorted.enumerated() {
            let spanEnd = index + 1 < sorted.count ? sorted[index + 1].timestamp : now
            let duration = spanEnd.timeIntervalSince(event.timestamp)
            guard duration > 0 else { continue }

            switch event.type {
            case .becameTogether:
                togetherSeconds += duration
            case .becameApart:
                apartSeconds += duration
            }
        }

        let secondsPerDay: TimeInterval = 86_400
        return CumulativeStats(
            totalDaysTogether: togetherSeconds / secondsPerDay,
            totalDaysApart: apartSeconds / secondsPerDay
        )
    }

    /// Every stretch apart, oldest first: from each parting (or the pairing)
    /// to the reunion that ended it; the last is open while still apart. A
    /// repeated event of the same kind — both partners tapping at once —
    /// doesn't start a new one. Mirrors separations in web/logic.js.
    public static func separations(events: [RelationshipEvent], pairedAt: Date? = nil) -> [Separation] {
        var result: [Separation] = []
        var openSince: Date?
        for event in timeline(events, pairedAt: pairedAt) {
            switch event.type {
            case .becameApart:
                if openSince == nil { openSince = event.timestamp }
            case .becameTogether:
                if let start = openSince {
                    result.append(Separation(start: start, end: event.timestamp))
                    openSince = nil
                }
            }
        }
        if let start = openSince {
            result.append(Separation(start: start, end: nil))
        }
        return result
    }

    /// Events oldest first, preceded by the implicit "apart" at pairing.
    private static func timeline(_ events: [RelationshipEvent], pairedAt: Date?) -> [RelationshipEvent] {
        var sorted = events.sorted { $0.timestamp < $1.timestamp }
        if let pairedAt, sorted.first.map({ pairedAt < $0.timestamp }) ?? true {
            sorted.insert(RelationshipEvent(id: "paired", type: .becameApart, timestamp: pairedAt, triggeredBy: ""), at: 0)
        }
        return sorted
    }
}
