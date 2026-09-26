// data.js: every Firestore read/write the web client makes, mirroring
// CoupleCountdown/Services/FirestoreService.swift field-for-field so the web
// app and the iPhone app can share one couple document. A person's pairing and
// name live on their account (users/{uid}), not the device, so every device
// they sign in on finds the same pairing. Takes a Firestore
// instance and uid rather than importing a config, so the same module runs in
// the browser (import map -> gstatic CDN) and in Node (npm `firebase`) for tests.

import {
  arrayUnion,
  addDoc,
  collection,
  deleteDoc,
  deleteField,
  doc,
  getDocs,
  onSnapshot,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} from "firebase/firestore";
import { dayFromStored, normalizedStart, PING_LIFETIME_MS, storedFromLocalDay } from "./logic.js";

// Same alphabet as JoinCodeGenerator.swift, no 0/O/1/I.
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export function generateJoinCode(length = 6) {
  const bytes = new Uint32Array(length);
  globalThis.crypto.getRandomValues(bytes);
  return Array.from(bytes, (n) => CODE_ALPHABET[n % CODE_ALPHABET.length]).join("");
}

export function normalizeCode(input) {
  return input.trim().toUpperCase();
}

export function makeApi(db, uid) {
  const coupleRef = (coupleId) => doc(db, "couples", coupleId);
  const userRef = () => doc(db, "users", uid);

  return {
    coupleRef,

    userRef,

    /** Name (and pairing, when known) on the account: merge, never clobber. */
    async saveProfile(fields) {
      await setDoc(userRef(), fields, { merge: true });
    },

    /**
     * Creates the couple doc with the caller as sole participant (§5.3) and
     * records it on the account in the same batch, so the pairing can never
     * exist without the account knowing about it.
     */
    async createCouple(coupleId, displayName, timeZone) {
      const batch = writeBatch(db);
      batch.set(coupleRef(coupleId), {
        status: "apart",
        participantUIDs: [uid],
        partnerProfiles: { [uid]: { displayName, timeZoneIdentifier: timeZone } },
        lastUpdatedBy: uid,
        lastUpdatedAt: Timestamp.now(),
        // Pairings start apart: the first stretch apart runs from here (no
        // event marks it), so the stats count it.
        pairedAt: Timestamp.now(),
      });
      batch.set(userRef(), { displayName, coupleId }, { merge: true });
      await batch.commit();
      // No expiry: a code stays joinable until the partner joins or the
      // pairing is cancelled (both enforced by the rules).
    },

    /**
     * Joins an existing couple. Two writes, because the rules' join path only
     * permits a couple-doc write that touches exactly participantUIDs.
     *
     * The account record goes in the *first* batch, with the join itself (a
     * different document, so the join rule still holds). It used to be in the
     * second: if that failed, the joiner was in the pairing but their account
     * never knew, and retrying Join was refused (already a participant): stuck
     * for good. Now a failed second write only leaves the name missing, which
     * ensurePartnerProfile fills in the next time the countdown loads.
     */
    async joinCouple(coupleId, displayName, timeZone) {
      const join = writeBatch(db);
      join.update(coupleRef(coupleId), { participantUIDs: arrayUnion(uid) });
      join.set(userRef(), { displayName, coupleId }, { merge: true });
      await join.commit();
      await updateDoc(coupleRef(coupleId), {
        [`partnerProfiles.${uid}`]: { displayName, timeZoneIdentifier: timeZone },
      });
    },

    /** Fills in this person's name/time zone on the couple doc if it's missing. */
    async ensurePartnerProfile(coupleId, displayName, timeZone) {
      await updateDoc(coupleRef(coupleId), {
        [`partnerProfiles.${uid}`]: { displayName, timeZoneIdentifier: timeZone },
      });
    },

    /**
     * Cancels a pairing nobody has joined yet (e.g. both partners tapped
     * Create). Marks it closed so its code can't be joined any more, and
     * detaches it from the account so the user can create or join another.
     */
    async cancelPairing(coupleId) {
      const batch = writeBatch(db);
      batch.update(coupleRef(coupleId), { closed: true });
      batch.set(userRef(), { coupleId: deleteField() }, { merge: true });
      await batch.commit();
    },

    /** Detaches a pairing that no longer exists or can't be read. */
    async forgetPairing() {
      await setDoc(userRef(), { coupleId: deleteField() }, { merge: true });
    },

    /**
     * Status change + history event in one batch so they can never disagree
     * (§8). The listener shows it at once; the returned promise settles when
     * the server has it: callers shouldn't wait on it to move on, or offline
     * nothing happens until the connection is back. `moveVisit` ({ id, start })
     * also moves a visit that's happening early, in the same write.
     */
    setStatus(coupleId, status, nextMeetupDate = null, moveVisit = null) {
      const batch = writeBatch(db);
      const fields = {
        status,
        lastUpdatedBy: uid,
        lastUpdatedAt: serverTimestamp(),
      };
      if (nextMeetupDate) fields.nextMeetupDate = Timestamp.fromDate(nextMeetupDate);
      batch.update(coupleRef(coupleId), fields);
      if (moveVisit) {
        batch.update(doc(collection(coupleRef(coupleId), "visits"), moveVisit.id), { start: Timestamp.fromDate(moveVisit.start) });
      }
      batch.set(doc(collection(coupleRef(coupleId), "events")), {
        type: status === "together" ? "became_together" : "became_apart",
        // When it was tapped, not when the server gets it: a reunion
        // confirmed offline would otherwise be logged whenever it reconnected.
        timestamp: Timestamp.now(),
        triggeredBy: uid,
      });
      return batch.commit();
    },

    /** Sets (or, with null, clears) what the countdown follows, without changing status. */
    async setNextMeetupDate(coupleId, date) {
      await updateDoc(coupleRef(coupleId), {
        nextMeetupDate: date ? Timestamp.fromDate(date) : deleteField(),
        lastUpdatedBy: uid,
        lastUpdatedAt: serverTimestamp(),
      });
    },

    // ---------- visits (planned meetups, with a time) ----------

    async addVisit(coupleId, { start, note }) {
      const visit = { id: globalThis.crypto.randomUUID(), start: normalizedStart(start), note: note || null, createdBy: uid };
      const fields = { start: Timestamp.fromDate(visit.start), createdBy: uid };
      if (visit.note) fields.note = visit.note;
      await setDoc(doc(collection(coupleRef(coupleId), "visits"), visit.id), fields);
      return visit;
    },

    async fetchVisits(coupleId) {
      const snap = await getDocs(collection(coupleRef(coupleId), "visits"));
      return snap.docs
        .map((d) => {
          const data = d.data();
          if (!data.start?.toDate) return null;
          return { id: d.id, start: data.start.toDate(), note: typeof data.note === "string" ? data.note : null, createdBy: data.createdBy };
        })
        .filter(Boolean);
    },

    async deleteVisit(coupleId, id) {
      await deleteDoc(doc(collection(coupleRef(coupleId), "visits"), id));
    },

    // ---------- important dates (calendar days) ----------

    /** `day` is any Date on the picked day (local); stored so it's the same day in every zone. */
    async addImportantDate(coupleId, { label, day, repeatsAnnually }) {
      const id = globalThis.crypto.randomUUID();
      await setDoc(doc(collection(coupleRef(coupleId), "importantDates"), id), {
        label,
        date: Timestamp.fromDate(storedFromLocalDay(day)),
        repeatsAnnually,
        createdBy: uid,
      });
      return id;
    },

    async deleteImportantDate(coupleId, id) {
      await deleteDoc(doc(collection(coupleRef(coupleId), "importantDates"), id));
    },

    async fetchImportantDates(coupleId) {
      const snap = await getDocs(collection(coupleRef(coupleId), "importantDates"));
      return snap.docs
        .map((d) => {
          const data = d.data();
          if (typeof data.label !== "string" || !data.date?.toDate) return null;
          return {
            id: d.id,
            label: data.label,
            // Local midnight of the stored *day*: read with UTC components,
            // not as an instant (see storedFromLocalDay).
            date: dayFromStored(data.date.toDate()),
            repeatsAnnually: data.repeatsAnnually === true,
            createdBy: data.createdBy,
          };
        })
        .filter(Boolean);
    },

    async sendPing(coupleId) {
      await addDoc(collection(coupleRef(coupleId), "pings"), {
        sentBy: uid,
        sentAt: serverTimestamp(),
        expiresAt: Timestamp.fromMillis(Date.now() + PING_LIFETIME_MS),
      });
    },

    /**
     * Both partners' pings from the last few days, live; unseenPings (logic.js)
     * picks out the ones to show. Filtered by time only: one field, so no
     * composite index. Returns the unsubscribe function.
     */
    watchRecentPings(coupleId, onChange, onError) {
      const cutoff = Timestamp.fromMillis(Date.now() - PING_LIFETIME_MS);
      const q = query(collection(coupleRef(coupleId), "pings"), where("sentAt", ">", cutoff));
      return onSnapshot(q, (snap) => {
        onChange(snap.docs
          .map((d) => {
            const data = d.data({ serverTimestamps: "estimate" });
            if (typeof data.sentBy !== "string" || !data.sentAt?.toDate) return null;
            return { id: d.id, sentBy: data.sentBy, sentAt: data.sentAt.toDate(), seenAt: data.seenAt?.toDate?.() ?? null };
          })
          .filter(Boolean));
      }, onError);
    },

    /** Marks the partner's pings seen, so every device on this account stops showing them. */
    async markPingsSeen(coupleId, ids) {
      if (!ids.length) return;
      const batch = writeBatch(db);
      for (const id of ids) batch.update(doc(collection(coupleRef(coupleId), "pings"), id), { seenAt: serverTimestamp() });
      await batch.commit();
    },

    async fetchEvents(coupleId) {
      const snap = await getDocs(collection(coupleRef(coupleId), "events"));
      return snap.docs
        .map((d) => {
          const data = d.data();
          return {
            id: d.id,
            type: data.type,
            timestamp: data.timestamp?.toDate?.() ?? null,
            triggeredBy: data.triggeredBy,
          };
        })
        .filter((e) => e.type && e.timestamp);
    },
  };
}
