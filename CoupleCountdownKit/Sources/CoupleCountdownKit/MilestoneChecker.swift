// MilestoneChecker.swift — pure logic for detecting celebration-worthy moments (DESIGN.md §7.3)

import Foundation

/// DESIGN.md §7.3 described milestone celebration as a v1 goal but no
/// implementation existed anywhere in the codebase until now — caught
/// while building out real end-to-end test coverage. Pure, testable
/// logic; the actual confetti/animation lives in the app target
/// (MilestoneCelebrationView), since this package stays UI-framework-free.
public enum MilestoneChecker {
    /// Round numbers worth celebrating, in ascending order.
    public static let roundDayMilestones = [7, 30, 100, 365, 500, 1000]

    /// True once the countdown target has passed while still "apart" —
    /// the moment worth celebrating even before either partner has
    /// tapped the status toggle yet.
    public static func countdownReachedZero(
        nextMeetupDate: Date?,
        status: RelationshipState.Status,
        now: Date = Date()
    ) -> Bool {
        guard status == .apart, let nextMeetupDate else { return false }
        return nextMeetupDate <= now
    }

    /// The largest round-number days-together milestone reached so far,
    /// if any — e.g. 100 once totalDaysTogether >= 100. Callers are
    /// responsible for tracking which milestones have already been shown
    /// so this doesn't re-celebrate the same one repeatedly.
    public static func roundDayMilestoneReached(totalDaysTogether: Double) -> Int? {
        let days = Int(totalDaysTogether)
        return roundDayMilestones.last(where: { $0 <= days })
    }
}
