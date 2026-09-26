// Emulator tests for firestore.rules (DESIGN.md §5.3).
// Run via `npm test` from firebase/: starts the Firestore emulator and
// runs this suite against it, then tears the emulator down.

const fs = require('fs');
const path = require('path');
const assert = require('assert');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} = require('firebase/firestore');

const PROJECT_ID = 'demo-couplecountdown';
const COUPLE_ID = 'ABCD23'; // stand-in join code
const UID_A = 'uidA';
const UID_B = 'uidB';
const UID_C = 'uidC'; // a third party who should never get in

let testEnv;

before(async function () {
  this.timeout(20000);
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

// Seeds a couple doc directly, bypassing rules: this is setup, not what's
// under test.
async function seedCouple(participantUIDs) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'couples', COUPLE_ID), {
      status: 'apart',
      nextMeetupDate: null,
      participantUIDs,
      lastUpdatedBy: participantUIDs[0],
      lastUpdatedAt: new Date(),
    });
  });
}

function coupleDoc(uid) {
  const ctx = uid ? testEnv.authenticatedContext(uid) : testEnv.unauthenticatedContext();
  return doc(ctx.firestore(), 'couples', COUPLE_ID);
}

describe('couples/{coupleId}: create', () => {
  it('allows creating a couple doc with exactly [self] as participantUIDs', async () => {
    await assertSucceeds(
      setDoc(coupleDoc(UID_A), {
        status: 'apart',
        nextMeetupDate: null,
        participantUIDs: [UID_A],
        lastUpdatedBy: UID_A,
        lastUpdatedAt: new Date(),
      })
    );
  });

  it('rejects creating a couple doc naming someone else as the participant', async () => {
    await assertFails(
      setDoc(coupleDoc(UID_A), {
        status: 'apart',
        nextMeetupDate: null,
        participantUIDs: [UID_B],
        lastUpdatedBy: UID_A,
        lastUpdatedAt: new Date(),
      })
    );
  });

  it('rejects an unauthenticated create', async () => {
    await assertFails(
      setDoc(coupleDoc(null), {
        status: 'apart',
        nextMeetupDate: null,
        participantUIDs: [],
        lastUpdatedBy: null,
        lastUpdatedAt: new Date(),
      })
    );
  });
});

describe('couples/{coupleId}: join while open', () => {
  it('lets a second, different uid append itself when a slot is open', async () => {
    await seedCouple([UID_A]);
    await assertSucceeds(
      updateDoc(coupleDoc(UID_B), { participantUIDs: [UID_A, UID_B] })
    );
  });

  it("lets a joiner record the pairing on their account in the same batch as the join", async () => {
    // What both clients do, so a failed follow-up write can't leave the
    // joiner in the pairing with an account that doesn't know it.
    await seedCouple([UID_A]);
    const db = testEnv.authenticatedContext(UID_B).firestore();
    const batch = writeBatch(db);
    batch.update(doc(db, 'couples', COUPLE_ID), { participantUIDs: [UID_A, UID_B] });
    batch.set(doc(db, 'users', UID_B), { displayName: 'Sam', coupleId: COUPLE_ID }, { merge: true });
    await assertSucceeds(batch.commit());
  });

  it('rejects a join write that also touches another field', async () => {
    await seedCouple([UID_A]);
    await assertFails(
      updateDoc(coupleDoc(UID_B), {
        participantUIDs: [UID_A, UID_B],
        status: 'together', // sneaking in an extra change alongside the join
      })
    );
  });

  it('a stranger CAN read the doc while a slot is still open (they hold the code)', async () => {
    await seedCouple([UID_A]);
    await assertSucceeds(getDoc(coupleDoc(UID_C)));
  });
});

describe('couples/{coupleId}: cancelled pairing', () => {
  it('lets the creator mark their still-open pairing closed', async () => {
    await seedCouple([UID_A]);
    await assertSucceeds(updateDoc(coupleDoc(UID_A), { closed: true }));
  });

  it('rejects cancelling once the partner has joined (cancel/join race)', async () => {
    await seedCouple([UID_A, UID_B]);
    await assertFails(updateDoc(coupleDoc(UID_A), { closed: true }));
  });

  it('rejects joining a pairing its creator cancelled', async () => {
    await seedCouple([UID_A]);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await updateDoc(doc(ctx.firestore(), 'couples', COUPLE_ID), { closed: true });
    });
    await assertFails(updateDoc(coupleDoc(UID_B), { participantUIDs: [UID_A, UID_B] }));
  });
});

describe('couples/{coupleId}: join while full', () => {
  it('rejects a third uid trying to join once both slots are filled', async () => {
    await seedCouple([UID_A, UID_B]);
    await assertFails(
      updateDoc(coupleDoc(UID_C), { participantUIDs: [UID_A, UID_B, UID_C] })
    );
  });
});

describe('couples/{coupleId}: stranger read while full', () => {
  it('rejects a non-participant reading the doc once both slots are filled', async () => {
    await seedCouple([UID_A, UID_B]);
    await assertFails(getDoc(coupleDoc(UID_C)));
  });

  it('rejects an unauthenticated read once both slots are filled', async () => {
    await seedCouple([UID_A, UID_B]);
    await assertFails(getDoc(coupleDoc(null)));
  });

  it('still lets an actual participant read the doc once both slots are filled', async () => {
    await seedCouple([UID_A, UID_B]);
    await assertSucceeds(getDoc(coupleDoc(UID_A)));
  });
});

describe('couples/{coupleId}: own participant edit', () => {
  it('lets a participant edit ordinary fields (e.g. status)', async () => {
    await seedCouple([UID_A, UID_B]);
    await assertSucceeds(
      updateDoc(coupleDoc(UID_A), {
        status: 'together',
        lastUpdatedBy: UID_A,
        lastUpdatedAt: new Date(),
      })
    );
  });

  it('rejects a non-participant editing ordinary fields', async () => {
    await seedCouple([UID_A, UID_B]);
    await assertFails(updateDoc(coupleDoc(UID_C), { status: 'together' }));
  });
});

describe('couples/{coupleId}: membership tamper attempt', () => {
  it('rejects a participant changing participantUIDs via a normal edit (e.g. removing the other partner)', async () => {
    await seedCouple([UID_A, UID_B]);
    await assertFails(
      updateDoc(coupleDoc(UID_A), { participantUIDs: [UID_A] })
    );
  });

  it('rejects a participant sneaking a third uid into participantUIDs directly', async () => {
    await seedCouple([UID_A, UID_B]);
    await assertFails(
      updateDoc(coupleDoc(UID_A), { participantUIDs: [UID_A, UID_B, UID_C] })
    );
  });
});

describe('couples/{coupleId}/{sub=**}: subcollections', () => {
  it('lets a participant write into a subcollection (e.g. events)', async () => {
    await seedCouple([UID_A, UID_B]);
    await assertSucceeds(
      setDoc(doc(testEnv.authenticatedContext(UID_A).firestore(), 'couples', COUPLE_ID, 'events', 'e1'), {
        type: 'became_together',
        timestamp: new Date(),
        triggeredBy: UID_A,
      })
    );
  });

  it('rejects a non-participant writing into a subcollection', async () => {
    await seedCouple([UID_A, UID_B]);
    await assertFails(
      setDoc(doc(testEnv.authenticatedContext(UID_C).firestore(), 'couples', COUPLE_ID, 'events', 'e1'), {
        type: 'became_together',
        timestamp: new Date(),
        triggeredBy: UID_C,
      })
    );
  });

  it('rejects a non-participant reading a subcollection', async () => {
    await seedCouple([UID_A, UID_B]);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'couples', COUPLE_ID, 'events', 'e1'), {
        type: 'became_together',
        timestamp: new Date(),
        triggeredBy: UID_A,
      });
    });
    await assertFails(
      getDoc(doc(testEnv.authenticatedContext(UID_C).firestore(), 'couples', COUPLE_ID, 'events', 'e1'))
    );
  });
});

describe('couples/{coupleId}: time tracking writes', () => {
  it('allows recording pairedAt when creating a pairing', async () => {
    await assertSucceeds(
      setDoc(doc(testEnv.authenticatedContext(UID_A).firestore(), 'couples', COUPLE_ID), {
        status: 'apart',
        participantUIDs: [UID_A],
        partnerProfiles: {},
        lastUpdatedBy: UID_A,
        lastUpdatedAt: new Date(),
        pairedAt: new Date(),
      })
    );
  });

  it('lets a partner say they met early: status, event, and the visit moved to now in one batch', async () => {
    await seedCouple([UID_A, UID_B]);
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'couples', COUPLE_ID, 'visits', 'v1'), {
        start: new Date(Date.now() + 86400000),
        createdBy: UID_A,
      });
    });
    const db = testEnv.authenticatedContext(UID_B).firestore();
    const now = new Date();
    const batch = writeBatch(db);
    batch.update(doc(db, 'couples', COUPLE_ID), { status: 'together', nextMeetupDate: now, lastUpdatedBy: UID_B });
    batch.update(doc(db, 'couples', COUPLE_ID, 'visits', 'v1'), { start: now });
    batch.set(doc(db, 'couples', COUPLE_ID, 'events', 'e1'), { type: 'became_together', timestamp: now, triggeredBy: UID_B });
    await assertSucceeds(batch.commit());
  });
});

describe('couples/{coupleId}/pings: "thinking of you"', () => {
  const since = new Date(Date.now() - 5 * 86400000);
  const recentPings = (uid) =>
    query(collection(testEnv.authenticatedContext(uid).firestore(), 'couples', COUPLE_ID, 'pings'), where('sentAt', '>', since));

  async function seedPing() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'couples', COUPLE_ID, 'pings', 'p1'), {
        sentBy: UID_B,
        sentAt: new Date(),
        expiresAt: new Date(Date.now() + 5 * 86400000),
      });
    });
  }

  it('lets the partner list recent pings and mark one seen (how it reaches them)', async () => {
    await seedCouple([UID_A, UID_B]);
    await seedPing();
    await assertSucceeds(getDocs(recentPings(UID_A)));
    await assertSucceeds(
      updateDoc(doc(testEnv.authenticatedContext(UID_A).firestore(), 'couples', COUPLE_ID, 'pings', 'p1'), { seenAt: new Date() })
    );
  });

  it('rejects a non-participant listing pings', async () => {
    await seedCouple([UID_A, UID_B]);
    await seedPing();
    await assertFails(getDocs(recentPings(UID_C)));
  });
});

function userDoc(asUid, ofUid) {
  const ctx = asUid ? testEnv.authenticatedContext(asUid) : testEnv.unauthenticatedContext();
  return doc(ctx.firestore(), 'users', ofUid);
}

describe('users/{userId}: per-account record', () => {
  it('lets an account write and read its own record', async () => {
    await assertSucceeds(setDoc(userDoc(UID_A, UID_A), { displayName: 'Alex', coupleId: COUPLE_ID }));
    await assertSucceeds(getDoc(userDoc(UID_A, UID_A)));
  });

  it("rejects reading someone else's record", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', UID_A), { displayName: 'Alex', coupleId: COUPLE_ID });
    });
    await assertFails(getDoc(userDoc(UID_B, UID_A)));
  });

  it("rejects writing someone else's record", async () => {
    await assertFails(setDoc(userDoc(UID_B, UID_A), { displayName: 'Mallory' }));
  });

  it('rejects unauthenticated reads and writes', async () => {
    await assertFails(getDoc(userDoc(null, UID_A)));
    await assertFails(setDoc(userDoc(null, UID_A), { displayName: 'Alex' }));
  });

  it('rejects unexpected fields', async () => {
    await assertFails(setDoc(userDoc(UID_A, UID_A), { displayName: 'Alex', isAdmin: true }));
  });

  it('rejects a non-string coupleId and an overlong displayName', async () => {
    await assertFails(setDoc(userDoc(UID_A, UID_A), { coupleId: 42 }));
    await assertFails(setDoc(userDoc(UID_A, UID_A), { displayName: 'x'.repeat(61) }));
  });

  it("pointing your record at a pairing you're not in grants no access to it", async () => {
    await seedCouple([UID_A, UID_B]);
    await assertSucceeds(setDoc(userDoc(UID_C, UID_C), { coupleId: COUPLE_ID }));
    await assertFails(getDoc(coupleDoc(UID_C)));
  });
});

// Sanity check that the test setup itself is meaningful: prove the rules
// file is actually being exercised, not vacuously passing.
describe('sanity check', () => {
  it('the deny-by-default baseline actually denies an obviously-bad write', async () => {
    await assertFails(
      setDoc(coupleDoc(null), { participantUIDs: [UID_A, UID_B, UID_C, 'uidD'] })
    );
  });
});
