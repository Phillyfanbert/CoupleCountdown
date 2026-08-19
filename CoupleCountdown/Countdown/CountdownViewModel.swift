// CountdownViewModel.swift — drives CountdownView from the synced RelationshipState (DESIGN.md §8)

import Foundation
import CoupleCountdownKit

@MainActor
final class CountdownViewModel: ObservableObject {
    @Published var promptForDate = false
    @Published var errorMessage: String?

    private let firestore: FirestoreService
    private let coupleId: String
    private let uid: String

    init(firestore: FirestoreService, coupleId: String, uid: String) {
        self.firestore = firestore
        self.coupleId = coupleId
        self.uid = uid
    }

    /// The apart/together toggle from DESIGN.md §8. "Leaving again" with
    /// no future date set prompts for one rather than silently showing a
    /// null/broken countdown, matching the edge case called out there.
    func toggleStatus(current: RelationshipState.Status, nextMeetupDate: Date?) async {
        let newStatus: RelationshipState.Status = current == .apart ? .together : .apart

        if newStatus == .apart && nextMeetupDate == nil {
            promptForDate = true
            return
        }

        do {
            try await firestore.setStatus(newStatus, coupleId: coupleId, uid: uid, nextMeetupDate: nil)
        } catch {
            errorMessage = "Couldn't update — check your connection and try again."
        }
    }

    /// Completes the "leaving again" transition once a date is supplied
    /// — this is also what fills the no-date-set empty state that applies
    /// right after pairing, not just the "leaving again" edge case (§6).
    func setNextMeetupDate(_ date: Date, currentStatus: RelationshipState.Status) async {
        do {
            try await firestore.setStatus(.apart, coupleId: coupleId, uid: uid, nextMeetupDate: date)
            promptForDate = false
        } catch {
            errorMessage = "Couldn't save the date — check your connection and try again."
        }
    }
}
