// CountdownViewModel.swift — drives CountdownView from the synced RelationshipState (DESIGN.md §8)

import Foundation
import CoupleCountdownKit

@MainActor
final class CountdownViewModel: ObservableObject {
    /// Why the visit sheet is open (nil = closed).
    enum VisitSheetPurpose: Equatable {
        /// "Leaving again" with nothing planned yet: saving also switches to apart.
        case leaving
        /// No meetup set, or it has passed: plan the next one.
        case plan
        /// Replace the meetup currently counted down to.
        case change
    }

    @Published var visitSheetPurpose: VisitSheetPurpose?
    @Published var errorMessage: String?

    private let firestore: FirestoreService
    private let coupleId: String
    private let uid: String

    init(firestore: FirestoreService, coupleId: String, uid: String) {
        self.firestore = firestore
        self.coupleId = coupleId
        self.uid = uid
    }

    /// Apart → together. Returns whether the write succeeded — callers use
    /// this to drive the instant local widget refresh from §5.2's sync
    /// pipeline convention (SyncCoordinator.applyLocalWrite).
    func markTogether() async -> Bool {
        errorMessage = nil
        do {
            try await firestore.setStatus(.together, coupleId: coupleId, uid: uid, nextMeetupDate: nil)
            return true
        } catch {
            errorMessage = "Couldn't update — check your connection and try again."
            return false
        }
    }

    /// Together → apart. Every goodbye is a new trip, so this counts down to
    /// the next *planned* visit — or asks for one if none is planned.
    /// Previously it only asked when no date had ever been set, so after the
    /// first trip "Leaving again" silently reused the old, already-passed
    /// date and there was no way on iPhone to enter the next one.
    ///
    /// Returns the meetup date it switched to, or nil when it's asking (the
    /// sheet opens) or the write failed.
    func leave() async -> Date? {
        errorMessage = nil
        do {
            let visits = try await firestore.fetchVisits(coupleId: coupleId)
            guard let next = MeetupPlanner.nextUpcoming(visits) else {
                visitSheetPurpose = .leaving
                return nil
            }
            try await firestore.setStatus(.apart, coupleId: coupleId, uid: uid, nextMeetupDate: next.start)
            return next.start
        } catch {
            errorMessage = "Couldn't update — check your connection and try again."
            return nil
        }
    }

    /// Saves the visit from the sheet and updates what the countdown follows.
    /// Returns the resulting state to apply locally, or nil on failure.
    func saveVisit(start: Date, note: String?, current: RelationshipState) async -> RelationshipState? {
        guard let purpose = visitSheetPurpose else { return nil }
        errorMessage = nil
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let visit = Visit(
            id: UUID().uuidString,
            start: MeetupPlanner.normalized(start),
            note: (trimmedNote?.isEmpty == false) ? trimmedNote : nil,
            createdBy: uid
        )
        do {
            try await firestore.addVisit(visit, coupleId: coupleId)
            var visits = try await firestore.fetchVisits(coupleId: coupleId)
            var updated = current

            switch purpose {
            case .leaving:
                let next = MeetupPlanner.nextUpcoming(visits)?.start ?? visit.start
                try await firestore.setStatus(.apart, coupleId: coupleId, uid: uid, nextMeetupDate: next)
                updated.status = .apart
                updated.nextMeetupDate = next
            case .plan, .change:
                if purpose == .change, let currentDate = current.nextMeetupDate,
                   let replaced = visits.first(where: { $0.id != visit.id && abs($0.start.timeIntervalSince(currentDate)) < 1 }) {
                    try await firestore.deleteVisit(id: replaced.id, coupleId: coupleId)
                    visits.removeAll { $0.id == replaced.id }
                }
                // "Change" replaces the current meetup outright (even one set
                // before visits existed); "plan" only fills a missing or
                // passed one.
                let resolved = MeetupPlanner.resolvedNextMeetup(
                    current: purpose == .change ? nil : current.nextMeetupDate,
                    visits: visits
                )
                if resolved != current.nextMeetupDate {
                    try await firestore.setNextMeetupDate(resolved, coupleId: coupleId, uid: uid)
                }
                updated.nextMeetupDate = resolved
            }
            updated.lastUpdatedBy = uid
            updated.lastUpdatedAt = Date()
            visitSheetPurpose = nil
            return updated
        } catch {
            errorMessage = "Couldn't save the visit — check your connection and try again."
            return nil
        }
    }
}
