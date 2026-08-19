// CumulativeStatsCalculator.swift — derives total days together/apart from the event log (DESIGN.md §7.2)

import Foundation

public struct CumulativeStats: Equatable, Sendable {
    public var totalDaysTogether: Double
    public var totalDaysApart: Double

    public init(totalDaysTogether: Double, totalDaysApart: Double) {
        self.totalDaysTogether = totalDaysTogether
        self.totalDaysApart = totalDaysApart
    }
}

public enum CumulativeStatsCalculator {
    /// Walks the append-only event log and sums the duration of each
    /// together/apart span (DESIGN.md §7.2) — derived, not stored. The
    /// final span (from the last event to `now`) counts toward whichever
    /// status it currently reflects, since the couple hasn't toggled
    /// since then.
    public static func calculate(events: [RelationshipEvent], now: Date = Date()) -> CumulativeStats {
        guard !events.isEmpty else {
            return CumulativeStats(totalDaysTogether: 0, totalDaysApart: 0)
        }

        let sorted = events.sorted { $0.timestamp < $1.timestamp }
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
}
