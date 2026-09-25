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

    private func userRef(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    // MARK: - Account (users/{uid})

    /// What a person's account records: the name their partner sees and the
    /// pairing they're in. Living on the account rather than the device is
    /// what lets the same person use the iPhone app and the web client at
    /// once and see one pairing.
    struct AccountProfile: Equatable {
        var displayName: String?
        var coupleId: String?
    }

    /// Merges the given fields into the account record (never clobbers).
    func saveProfile(uid: String, displayName: String? = nil, coupleId: String? = nil) async throws {
        var fields: [String: Any] = [:]
        if let displayName { fields["displayName"] = displayName }
        if let coupleId { fields["coupleId"] = coupleId }
        try await userRef(uid).setData(fields, merge: true)
    }

    func deleteProfile(uid: String) async throws {
        try await userRef(uid).delete()
    }

    /// Watches the account record. Delivers only server-confirmed state:
    /// Firestore reports this device's own writes immediately, before the
    /// server has them, and acting on that after "Create" would open the new
    /// pairing before the server had stored it — the rules deny reading a
    /// pairing that doesn't exist yet, and a denied listener never recovers.
    /// (Found in the web client, which shares these rules.)
    func listenToProfile(
        uid: String,
        onChange: @escaping (Result<AccountProfile, Error>) -> Void
    ) -> ListenerRegistration {
        userRef(uid).addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
            if let error {
                onChange(.failure(error))
                return
            }
            guard let snapshot, !snapshot.metadata.hasPendingWrites else { return }
            // Offline with nothing cached: the account's state isn't known yet.
            if snapshot.metadata.isFromCache && !snapshot.exists { return }
            let data = snapshot.data() ?? [:]
            onChange(.success(AccountProfile(
                displayName: data["displayName"] as? String,
                coupleId: data["coupleId"] as? String
            )))
        }
    }

    // MARK: - Pairing (§5.3)

    /// Creates a new couple doc with the caller as the sole participant, and
    /// records it on the caller's account in the same batch — so a pairing can
    /// never exist without the account knowing about it.
    func createCouple(coupleId: String, uid: String, displayName: String, timeZoneIdentifier: String) async throws {
        let state = RelationshipState(
            status: .apart,
            nextMeetupDate: nil,
            participantUIDs: [uid],
            partnerProfiles: [uid: PartnerProfile(displayName: displayName, timeZoneIdentifier: timeZoneIdentifier)],
            lastUpdatedBy: uid,
            lastUpdatedAt: Date(),
            // Pairings start apart; this is where the first stretch apart
            // begins for the stats (no event marks it).
            pairedAt: Date()
        )
        let batch = db.batch()
        try batch.setData(from: state, forDocument: coupleRef(coupleId))
        batch.setData(["displayName": displayName, "coupleId": coupleId], forDocument: userRef(uid), merge: true)
        try await batch.commit()
        // No expiry: a code stays joinable until the partner joins or the
        // pairing is cancelled (both enforced by the rules). It used to get
        // a 48-hour codeExpiresAt here, which nothing ever enforced.
    }

    /// Joins an existing couple doc. Two writes, because the rules' join
    /// path only allows a couple-doc write that touches *exactly*
    /// participantUIDs (firebase/test/rules.test.js "join while open").
    ///
    /// The account record is written in the *first* batch, alongside the
    /// join itself (a different document, so the join rule still holds).
    /// It used to be in the second: if that one failed, the joiner was in
    /// the pairing but their account never knew — and retrying Join was
    /// refused because they were already a participant, so they were stuck
    /// for good. Now the second write only adds the name/time zone; if it
    /// fails, `ensurePartnerProfile` fills the profile in the next time the
    /// countdown loads.
    func joinCouple(coupleId: String, uid: String, displayName: String, timeZoneIdentifier: String) async throws {
        let join = db.batch()
        join.updateData(["participantUIDs": FieldValue.arrayUnion([uid])], forDocument: coupleRef(coupleId))
        join.setData(["displayName": displayName, "coupleId": coupleId], forDocument: userRef(uid), merge: true)
        try await join.commit()

        try await coupleRef(coupleId).updateData([
            "partnerProfiles.\(uid)": [
                "displayName": displayName,
                "timeZoneIdentifier": timeZoneIdentifier,
            ],
        ])
    }

    /// Fills in this person's name/time zone on the couple doc if it's
    /// missing (a join whose second write failed).
    func ensurePartnerProfile(coupleId: String, uid: String, displayName: String, timeZoneIdentifier: String) async throws {
        try await coupleRef(coupleId).updateData([
            "partnerProfiles.\(uid)": [
                "displayName": displayName,
                "timeZoneIdentifier": timeZoneIdentifier,
            ],
        ])
    }

    /// Cancels a pairing nobody has joined yet (e.g. both partners tapped
    /// Create): marks it closed so the rules refuse any further join, and
    /// detaches it from the account so the user can create or join another.
    func cancelPairing(coupleId: String, uid: String) async throws {
        let batch = db.batch()
        batch.updateData(["closed": true], forDocument: coupleRef(coupleId))
        batch.setData(["coupleId": FieldValue.delete()], forDocument: userRef(uid), merge: true)
        try await batch.commit()
    }

    /// Detaches a pairing this account can't open (the countdown's "Leave
    /// this pairing"), so it can create or join another. Matches the web's
    /// forgetPairing.
    func forgetPairing(uid: String) async throws {
        try await userRef(uid).setData(["coupleId": FieldValue.delete()], merge: true)
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
    /// Errors go to `onError` — they used to be dropped, and a pairing this
    /// account couldn't read left the countdown on "Loading…" for good.
    func listenToCouple(
        coupleId: String,
        onChange: @escaping (RelationshipState) -> Void,
        onError: @escaping (Error) -> Void
    ) -> ListenerRegistration {
        coupleRef(coupleId).addSnapshotListener { snapshot, error in
            if let error {
                onError(error)
                return
            }
            // .estimate, so this device's own change shows the moment it's
            // made — even offline, still queued for the server. Pending
            // snapshots used to fail to decode and were dropped, so an offline
            // "Yes, we're together!" changed nothing on screen.
            guard let snapshot,
                  let state = try? snapshot.data(as: RelationshipState.self, with: .estimate)
            else { return }
            onChange(state)
        }
    }

    // MARK: - Status toggle (§8)

    /// Batched so the status change and its history-log entry can never
    /// disagree (DESIGN.md §8 "Write atomicity") — a dropped connection
    /// between two separate writes could otherwise leave them
    /// inconsistent.
    ///
    /// Returns as soon as the change is applied on this device, without
    /// waiting for the server: offline (an airport arrivals hall) the app
    /// moves on at once and Firestore sends it when the connection is back.
    /// Waiting used to leave "Yes, we're together!" doing nothing visible
    /// until then. `onFailure` hears if the server rejects it.
    ///
    /// `movingVisit` also moves a visit's start in the same write — used when
    /// a couple meets before the planned time (MeetupPlanner.visitMetEarly).
    func setStatus(
        _ status: RelationshipState.Status,
        coupleId: String,
        uid: String,
        nextMeetupDate: Date?,
        movingVisit: (id: String, start: Date)? = nil,
        onFailure: @escaping (Error) -> Void
    ) {
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

        if let movingVisit {
            batch.updateData(
                ["start": Timestamp(date: movingVisit.start)],
                forDocument: coupleRef(coupleId).collection("visits").document(movingVisit.id)
            )
        }

        let eventType: RelationshipEvent.EventType = status == .together ? .becameTogether : .becameApart
        let eventRef = coupleRef(coupleId).collection("events").document()
        batch.setData(
            [
                "type": eventType.rawValue,
                // The moment it was tapped, not when the server gets it: a
                // reunion confirmed offline would otherwise be logged hours
                // late, whenever the phone reconnected.
                "timestamp": Timestamp(date: Date()),
                "triggeredBy": uid,
            ],
            forDocument: eventRef
        )

        batch.commit { error in
            if let error { onFailure(error) }
        }
    }

    /// Sets (or, with nil, clears) the meetup the main countdown and the
    /// widget count down to, without changing the apart/together status —
    /// used when visits are planned or removed.
    func setNextMeetupDate(_ date: Date?, coupleId: String, uid: String) async throws {
        try await coupleRef(coupleId).updateData([
            "nextMeetupDate": date.map { Timestamp(date: $0) as Any } ?? FieldValue.delete(),
            "lastUpdatedBy": uid,
            "lastUpdatedAt": FieldValue.serverTimestamp(),
        ])
    }

    // MARK: - Visits (planned meetups)

    func addVisit(_ visit: Visit, coupleId: String) async throws {
        var fields: [String: Any] = [
            "start": Timestamp(date: visit.start),
            "createdBy": visit.createdBy,
        ]
        if let note = visit.note, !note.isEmpty { fields["note"] = note }
        try await coupleRef(coupleId).collection("visits").document(visit.id).setData(fields)
    }

    func fetchVisits(coupleId: String) async throws -> [Visit] {
        let snapshot = try await coupleRef(coupleId).collection("visits").getDocuments()
        return snapshot.documents.compactMap { doc in
            guard
                let start = doc.get("start") as? Timestamp,
                let createdBy = doc.get("createdBy") as? String
            else { return nil }
            return Visit(id: doc.documentID, start: start.dateValue(), note: doc.get("note") as? String, createdBy: createdBy)
        }
    }

    func deleteVisit(id: String, coupleId: String) async throws {
        try await coupleRef(coupleId).collection("visits").document(id).delete()
    }

    // MARK: - Important dates (§7.4)

    func deleteImportantDate(id: String, coupleId: String) async throws {
        try await coupleRef(coupleId).collection("importantDates").document(id).delete()
    }

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
        // expiresAt is computed client-side (server timestamp isn't known
        // until the write resolves) — fine, since a few seconds of clock
        // skew is irrelevant against a multi-day TTL window.
        try await coupleRef(coupleId).collection("pings").addDocument(data: [
            "sentBy": uid,
            "sentAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: Date().addingTimeInterval(ThinkingOfYouPing.lifetime)),
        ])
    }

    /// Both partners' pings from the last `ThinkingOfYouPing.lifetime`,
    /// live; `ThinkingOfYouPing.unseen` picks out the ones to show. Filtered
    /// by time only (one field, so no composite index needed) — it's a
    /// handful of documents.
    func listenToRecentPings(
        coupleId: String,
        now: Date = Date(),
        onChange: @escaping ([ThinkingOfYouPing]) -> Void
    ) -> ListenerRegistration {
        let cutoff = Timestamp(date: now.addingTimeInterval(-ThinkingOfYouPing.lifetime))
        return coupleRef(coupleId).collection("pings")
            .whereField("sentAt", isGreaterThan: cutoff)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                onChange(snapshot.documents.compactMap { doc in
                    guard
                        let sentBy = doc.get("sentBy") as? String,
                        let sentAt = doc.get("sentAt", serverTimestampBehavior: .estimate) as? Timestamp
                    else { return nil }
                    return ThinkingOfYouPing(
                        id: doc.documentID,
                        sentBy: sentBy,
                        sentAt: sentAt.dateValue(),
                        expiresAt: (doc.get("expiresAt") as? Timestamp)?.dateValue(),
                        seenAt: (doc.get("seenAt", serverTimestampBehavior: .estimate) as? Timestamp)?.dateValue()
                    )
                })
            }
    }

    /// Marks the partner's pings as seen, so every device on this account
    /// (and the widget) stops showing them.
    func markPingsSeen(ids: [String], coupleId: String) async throws {
        guard !ids.isEmpty else { return }
        let batch = db.batch()
        for id in ids {
            batch.updateData(["seenAt": FieldValue.serverTimestamp()], forDocument: coupleRef(coupleId).collection("pings").document(id))
        }
        try await batch.commit()
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
