// FirestoreService.swift: all Firestore SDK reads/writes; app-target only, never the widget (DESIGN.md §5.6)

import Foundation
import FirebaseFirestore
import CoupleCountdownKit

/// Every Firestore SDK call in the app lives here (DESIGN.md §5.6): the
/// widget target never imports FirebaseFirestore at all; it only does its
/// own lightweight REST fetch (WidgetFirestoreClient, §5.5).
///
/// UNVERIFIED: written without Xcode available to compile against (see
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
        /// First name.
        var displayName: String?
        var lastName: String?
        var coupleId: String?
    }

    /// Merges the given fields into the account record (never clobbers).
    func saveProfile(uid: String, displayName: String? = nil, lastName: String? = nil, coupleId: String? = nil) async throws {
        var fields: [String: Any] = [:]
        if let displayName { fields["displayName"] = displayName }
        if let lastName { fields["lastName"] = lastName }
        if let coupleId { fields["coupleId"] = coupleId }
        try await userRef(uid).setData(fields, merge: true)
    }

    func deleteProfile(uid: String) async throws {
        try await userRef(uid).delete()
    }

    /// Watches the account record. Delivers only server-confirmed state:
    /// Firestore reports this device's own writes immediately, before the
    /// server has them, and acting on that after "Create" would open the new
    /// pairing before the server had stored it: the rules deny reading a
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
                lastName: data["lastName"] as? String,
                coupleId: data["coupleId"] as? String
            )))
        }
    }

    // MARK: - Pairing (§5.3)

    /// Creates a new couple doc with the caller as the sole participant, and
    /// records it on the caller's account in the same batch, so a pairing can
    /// never exist without the account knowing about it.
    func createCouple(coupleId: String, uid: String, displayName: String, lastName: String?, timeZoneIdentifier: String) async throws {
        let state = RelationshipState(
            status: .apart,
            nextMeetupDate: nil,
            participantUIDs: [uid],
            partnerProfiles: [uid: PartnerProfile(displayName: displayName, lastName: lastName, timeZoneIdentifier: timeZoneIdentifier)],
            lastUpdatedBy: uid,
            lastUpdatedAt: Date(),
            // Pairings start apart; this is where the first stretch apart
            // begins for the stats (no event marks it).
            pairedAt: Date()
        )
        let batch = db.batch()
        try batch.setData(from: state, forDocument: coupleRef(coupleId))
        var account: [String: Any] = ["displayName": displayName, "coupleId": coupleId]
        if let lastName { account["lastName"] = lastName }
        batch.setData(account, forDocument: userRef(uid), merge: true)
        try await batch.commit()
        // No expiry: a code stays joinable until the partner joins or the
        // pairing is cancelled (both enforced by the rules). It used to get
        // a 48-hour codeExpiresAt here, which nothing ever enforced.
    }

    /// Whose pairing a code belongs to, for the "Pair with Alex Smith?"
    /// confirmation before joining, so nobody pairs with the wrong person
    /// by a mistyped code.
    struct JoinPreview: Equatable {
        let coupleId: String
        /// The code owner's first and last name.
        let partnerName: String
    }

    enum JoinPreviewProblem: Error, Equatable {
        /// No pairing with that code, or it already has two people (the rules
        /// can't tell the two apart to someone outside it).
        case notFound
        /// Its owner cancelled it.
        case cancelled
        /// The code is this account's own.
        case ownCode
        /// Someone else's request is already waiting for the creator.
        case anotherRequestWaiting
    }

    func joinPreview(coupleId: String, uid: String) async throws -> JoinPreview {
        let snapshot: DocumentSnapshot
        do {
            snapshot = try await coupleRef(coupleId).getDocument(source: .server)
        } catch let error as FirestoreErrorCode where error.code == .permissionDenied {
            throw JoinPreviewProblem.notFound
        }
        guard snapshot.exists, let state = try? snapshot.data(as: RelationshipState.self) else {
            throw JoinPreviewProblem.notFound
        }
        if snapshot.get("closed") as? Bool == true { throw JoinPreviewProblem.cancelled }
        if state.participantUIDs.contains(uid) { throw JoinPreviewProblem.ownCode }
        guard state.participantUIDs.count < 2 else { throw JoinPreviewProblem.notFound }
        if let waiting = state.joinRequest, waiting.uid != uid { throw JoinPreviewProblem.anotherRequestWaiting }
        let owner = state.participantUIDs.first.flatMap { state.partnerProfiles[$0] }
        return JoinPreview(coupleId: coupleId, partnerName: owner?.fullName ?? "your partner")
    }

    /// Asks to join a partner's pairing. Pairing takes both people: the
    /// request (with this person's name) goes on the couple doc for the
    /// creator to approve; only their approval adds this person. In the same
    /// batch the account points at the pairing, so every device on it shows
    /// the wait, and `discarding` (this person's own unused code, when both
    /// of them tapped Create) is closed, so it can never be joined afterwards.
    func requestToJoin(
        coupleId: String,
        uid: String,
        displayName: String,
        lastName: String?,
        timeZoneIdentifier: String,
        discarding ownCode: String? = nil
    ) async throws {
        let batch = db.batch()
        var request: [String: Any] = [
            "uid": uid,
            "displayName": displayName,
            "timeZoneIdentifier": timeZoneIdentifier,
            "requestedAt": Timestamp(date: Date()),
        ]
        if let lastName, !lastName.isEmpty { request["lastName"] = lastName }
        batch.updateData(["joinRequest": request], forDocument: coupleRef(coupleId))
        var account: [String: Any] = ["displayName": displayName, "coupleId": coupleId]
        if let lastName { account["lastName"] = lastName }
        batch.setData(account, forDocument: userRef(uid), merge: true)
        if let ownCode, ownCode != coupleId {
            batch.updateData(Self.closing, forDocument: coupleRef(ownCode))
        }
        try await batch.commit()
    }

    /// Closing a code also clears any request waiting on it: left behind, the
    /// person who asked sat on "Waiting for … to approve" for good.
    private static let closing: [String: Any] = ["closed": true, "joinRequest": FieldValue.delete()]

    /// Takes back a request that's still waiting, and detaches the account.
    func withdrawJoinRequest(coupleId: String, uid: String) async throws {
        let batch = db.batch()
        batch.updateData(["joinRequest": FieldValue.delete()], forDocument: coupleRef(coupleId))
        batch.setData(["coupleId": FieldValue.delete()], forDocument: userRef(uid), merge: true)
        try await batch.commit()
    }

    /// The creator approves: the person who asked joins, with their name.
    /// The rules only allow adding the uid on the current request, so a stale
    /// screen can't approve someone who has since withdrawn.
    func approveJoinRequest(_ request: JoinRequest, coupleId: String) async throws {
        try await coupleRef(coupleId).updateData([
            "participantUIDs": FieldValue.arrayUnion([request.uid]),
            "partnerProfiles.\(request.uid)": Self.profileFields(
                displayName: request.displayName,
                lastName: request.lastName,
                timeZoneIdentifier: request.timeZoneIdentifier
            ),
            "joinRequest": FieldValue.delete(),
        ])
    }

    /// The creator declines: the request goes, and the code stays open.
    func declineJoinRequest(coupleId: String) async throws {
        try await coupleRef(coupleId).updateData(["joinRequest": FieldValue.delete()])
    }

    /// Fills in this person's name/time zone on the couple doc if it's
    /// missing (a join whose second write failed).
    func ensurePartnerProfile(coupleId: String, uid: String, displayName: String, lastName: String?, timeZoneIdentifier: String) async throws {
        try await coupleRef(coupleId).updateData([
            "partnerProfiles.\(uid)": Self.profileFields(displayName: displayName, lastName: lastName, timeZoneIdentifier: timeZoneIdentifier),
        ])
    }

    private static func profileFields(displayName: String, lastName: String?, timeZoneIdentifier: String) -> [String: Any] {
        var fields: [String: Any] = ["displayName": displayName, "timeZoneIdentifier": timeZoneIdentifier]
        if let lastName, !lastName.isEmpty { fields["lastName"] = lastName }
        return fields
    }


    /// Cancels a pairing nobody has joined yet (e.g. both partners tapped
    /// Create): marks it closed so the rules refuse any further join, and
    /// detaches it from the account so the user can create or join another.
    func cancelPairing(coupleId: String, uid: String) async throws {
        let batch = db.batch()
        batch.updateData(Self.closing, forDocument: coupleRef(coupleId))
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
    /// The couple doc from the server when reachable, otherwise this device's
    /// copy (which includes its own not-yet-synced changes). For following
    /// the plan after a change, which mustn't fail just for being offline.
    func currentCouple(coupleId: String) async throws -> RelationshipState {
        try await coupleRef(coupleId).getDocument().data(as: RelationshipState.self, with: .estimate)
    }

    func fetchCouple(coupleId: String) async throws -> RelationshipState {
        try await coupleRef(coupleId).getDocument(source: .server).data(as: RelationshipState.self)
    }

    /// Mechanism #1: realtime listener while the app is foregrounded.
    /// Caller owns the returned registration's lifetime and must call
    /// `.remove()`: SyncCoordinator attaches/detaches this around
    /// scenePhase changes.
    /// Errors go to `onError`: they used to be dropped, and a pairing this
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
            // made, even offline, still queued for the server. Pending
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
    /// disagree (DESIGN.md §8 "Write atomicity"): a dropped connection
    /// between two separate writes could otherwise leave them
    /// inconsistent.
    ///
    /// Returns as soon as the change is applied on this device, without
    /// waiting for the server: offline (an airport arrivals hall) the app
    /// moves on at once and Firestore sends it when the connection is back.
    /// Waiting used to leave "Yes, we're together!" doing nothing visible
    /// until then. `onFailure` hears if the server rejects it.
    ///
    /// `movingVisit` also moves a visit's start in the same write, used when
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
    /// widget count down to, without changing the apart/together status:
    /// used when visits are planned or removed.
    // Plan writes (the meetup date, visits, important dates) apply on this
    // device at once and sync when the connection allows, like status
    // changes: they used to wait for the server, so offline the Save button
    // spun until reconnecting. `onFailure` hears if the server rejects one.

    func setNextMeetupDate(_ date: Date?, coupleId: String, uid: String, onFailure: @escaping (Error) -> Void) {
        coupleRef(coupleId).updateData([
            "nextMeetupDate": date.map { Timestamp(date: $0) as Any } ?? FieldValue.delete(),
            "lastUpdatedBy": uid,
            "lastUpdatedAt": FieldValue.serverTimestamp(),
        ]) { error in
            if let error { onFailure(error) }
        }
    }

    // MARK: - Visits (planned meetups)

    func addVisit(_ visit: Visit, coupleId: String, onFailure: @escaping (Error) -> Void) {
        var fields: [String: Any] = [
            "start": Timestamp(date: visit.start),
            "createdBy": visit.createdBy,
        ]
        if let note = visit.note, !note.isEmpty { fields["note"] = note }
        coupleRef(coupleId).collection("visits").document(visit.id).setData(fields) { error in
            if let error { onFailure(error) }
        }
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

    func deleteVisit(id: String, coupleId: String, onFailure: @escaping (Error) -> Void) {
        coupleRef(coupleId).collection("visits").document(id).delete { error in
            if let error { onFailure(error) }
        }
    }

    // MARK: - Important dates (§7.4)

    func deleteImportantDate(id: String, coupleId: String, onFailure: @escaping (Error) -> Void) {
        coupleRef(coupleId).collection("importantDates").document(id).delete { error in
            if let error { onFailure(error) }
        }
    }

    func addImportantDate(_ date: ImportantDate, coupleId: String, onFailure: @escaping (Error) -> Void) {
        coupleRef(coupleId).collection("importantDates").document(date.id).setData([
            "label": date.label,
            "date": Timestamp(date: date.date),
            "repeatsAnnually": date.repeatsAnnually,
            "createdBy": date.createdBy,
        ]) { error in
            if let error { onFailure(error) }
        }
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
        // until the write resolves): fine, since a few seconds of clock
        // skew is irrelevant against a multi-day TTL window.
        try await coupleRef(coupleId).collection("pings").addDocument(data: [
            "sentBy": uid,
            "sentAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: Date().addingTimeInterval(ThinkingOfYouPing.lifetime)),
        ])
    }

    /// Both partners' pings from the last `ThinkingOfYouPing.lifetime`,
    /// live; `ThinkingOfYouPing.unseen` picks out the ones to show. Filtered
    /// by time only (one field, so no composite index needed): it's a
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
