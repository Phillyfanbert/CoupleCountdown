// FirestoreService.swift — all Firestore SDK reads/writes; app-target only, never the widget (DESIGN.md §5.6)

import Foundation
import FirebaseFirestore
import CoupleCountdownKit

/// Every Firestore SDK call in the app lives here (DESIGN.md §5.6) — the
/// widget target never imports FirebaseFirestore at all; it only does its
/// own lightweight REST fetch (WidgetFirestoreClient, §5.5).
///
/// UNVERIFIED — written without Xcode available to compile against (see
/// DESIGN.md v0.3). Method names/signatures for FirebaseFirestore's
/// Codable support (`data(as:)`, `setData(from:)`) are believed correct
/// for the modern SDK but not compiled.
final class FirestoreService {
    private let db = Firestore.firestore()

    private func coupleRef(_ coupleId: String) -> DocumentReference {
        db.collection("couples").document(coupleId)
    }

    // MARK: - Pairing (§5.3)

    /// Creates a new couple doc with the caller as the sole participant.
    func createCouple(coupleId: String, uid: String, displayName: String, timeZoneIdentifier: String) async throws {
        let state = RelationshipState(
            status: .apart,
            nextMeetupDate: nil,
            participantUIDs: [uid],
            partnerProfiles: [uid: PartnerProfile(displayName: displayName, timeZoneIdentifier: timeZoneIdentifier)],
            lastUpdatedBy: uid,
            lastUpdatedAt: Date()
        )
        try await coupleRef(coupleId).setData(from: state)
        // codeExpiresAt (§5.3 point 6) is Firestore-lifecycle-only
        // metadata, not modeled in RelationshipState — kept out of the
        // create write so the Security Rules' create check
        // (`participantUIDs == [request.auth.uid]`) can stay a simple
        // equality test against the whole document.
        try await coupleRef(coupleId).updateData([
            "codeExpiresAt": Timestamp(date: Date().addingTimeInterval(48 * 3600)),
        ])
    }

    /// Joins an existing couple doc. Deliberately TWO separate writes:
    /// firebase/firestore.rules' join path only allows a write that
    /// touches *exactly* participantUIDs (verified in
    /// firebase/test/rules.test.js's "join while open" tests — a write
    /// that also sets other fields is rejected). Setting the profile and
    /// clearing codeExpiresAt has to happen in a second write, made as an
    /// established participant under the rules' "existing participant
    /// editing anything except participantUIDs" branch.
    func joinCouple(coupleId: String, uid: String, displayName: String, timeZoneIdentifier: String) async throws {
        try await coupleRef(coupleId).updateData([
            "participantUIDs": FieldValue.arrayUnion([uid]),
        ])
        try await coupleRef(coupleId).updateData([
            "partnerProfiles.\(uid)": [
                "displayName": displayName,
                "timeZoneIdentifier": timeZoneIdentifier,
            ],
            "codeExpiresAt": FieldValue.delete(),
        ])
    }

    // MARK: - Sync (§5.2)

    /// Mechanism #2: one-shot fetch on launch/foreground, from the server
    /// rather than the SDK's local cache, so opening the app is always
    /// immediately fresh.
    func fetchCouple(coupleId: String) async throws -> RelationshipState {
        try await coupleRef(coupleId).getDocument(source: .server).data(as: RelationshipState.self)
    }

    /// Mechanism #1: realtime listener while the app is foregrounded.
    /// Caller owns the returned registration's lifetime and must call
    /// `.remove()` — SyncCoordinator attaches/detaches this around
    /// scenePhase changes.
    func listenToCouple(coupleId: String, onChange: @escaping (RelationshipState) -> Void) -> ListenerRegistration {
        coupleRef(coupleId).addSnapshotListener { snapshot, _ in
            guard let snapshot, let state = try? snapshot.data(as: RelationshipState.self) else { return }
            onChange(state)
        }
    }

    // MARK: - Status toggle (§8)

    /// Batched so the status change and its history-log entry can never
    /// disagree (DESIGN.md §8 "Write atomicity") — a dropped connection
    /// between two separate writes could otherwise leave them
    /// inconsistent.
    func setStatus(
        _ status: RelationshipState.Status,
        coupleId: String,
        uid: String,
        nextMeetupDate: Date?
    ) async throws {
        let batch = db.batch()

        var fields: [String: Any] = [
            "status": status.rawValue,
            "lastUpdatedBy": uid,
            "lastUpdatedAt": FieldValue.serverTimestamp(),
        ]
        if let nextMeetupDate {
            fields["nextMeetupDate"] = Timestamp(date: nextMeetupDate)
        }
        batch.updateData(fields, forDocument: coupleRef(coupleId))

        let eventType: RelationshipEvent.EventType = status == .together ? .becameTogether : .becameApart
        let eventRef = coupleRef(coupleId).collection("events").document()
        batch.setData(
            [
                "type": eventType.rawValue,
                "timestamp": FieldValue.serverTimestamp(),
                "triggeredBy": uid,
            ],
            forDocument: eventRef
        )

        try await batch.commit()
    }

    // MARK: - Important dates (§7.4)

    func addImportantDate(_ date: ImportantDate, coupleId: String) async throws {
        try await coupleRef(coupleId).collection("importantDates").document(date.id).setData([
            "label": date.label,
            "date": Timestamp(date: date.date),
            "repeatsAnnually": date.repeatsAnnually,
            "createdBy": date.createdBy,
        ])
    }

    func fetchImportantDates(coupleId: String) async throws -> [ImportantDate] {
        let snapshot = try await coupleRef(coupleId).collection("importantDates").getDocuments()
        return snapshot.documents.compactMap { doc in
            guard
                let label = doc.get("label") as? String,
                let timestamp = doc.get("date") as? Timestamp,
                let repeatsAnnually = doc.get("repeatsAnnually") as? Bool,
                let createdBy = doc.get("createdBy") as? String
            else { return nil }
            return ImportantDate(
                id: doc.documentID,
                label: label,
                date: timestamp.dateValue(),
                repeatsAnnually: repeatsAnnually,
                createdBy: createdBy
            )
        }
    }

    // MARK: - Thinking of you (§7.1)

    func sendPing(coupleId: String, uid: String) async throws {
        try await coupleRef(coupleId).collection("pings").addDocument(data: [
            "sentBy": uid,
            "sentAt": FieldValue.serverTimestamp(),
        ])
    }

    // MARK: - Stats (§7.2)

    func fetchEvents(coupleId: String) async throws -> [RelationshipEvent] {
        let snapshot = try await coupleRef(coupleId).collection("events").getDocuments()
        return snapshot.documents.compactMap { doc in
            guard
                let typeString = doc.get("type") as? String,
                let type = RelationshipEvent.EventType(rawValue: typeString),
                let timestamp = doc.get("timestamp") as? Timestamp,
                let triggeredBy = doc.get("triggeredBy") as? String
            else { return nil }
            return RelationshipEvent(id: doc.documentID, type: type, timestamp: timestamp.dateValue(), triggeredBy: triggeredBy)
        }
    }
}
