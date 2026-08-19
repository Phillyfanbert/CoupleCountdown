# CoupleCountdown — Design Document

Status: **Draft v0.3** — planning, not yet implemented.

## 1. Concept

A two-person iOS app for couples (e.g. long-distance relationships) that shows
a shared, synced countdown to their next time together. Both partners see the
identical countdown on their phones, in Home Screen / Lock Screen widgets and
optionally a Live Activity, and can update the shared state ("we're together
now" / "leaving again") from either device.

Comparable existing apps: *Timestamp*, *Tondr*, *Lasting*.

## 2. Hard constraint: $0 cost

**This project must cost exactly $0 to build and run, with no exceptions.**
This is a hard rule, not a preference — every architecture, tooling, and
distribution decision in this document is filtered through it, and any
future proposal that breaks it should be rejected or redesigned before being
added here.

**Correction from v0.1:** the earlier draft picked CloudKit specifically to
satisfy this rule. That reasoning was wrong. Verified against current Apple
documentation and multiple independent sources: **both the iCloud/CloudKit
capability and the Push Notifications entitlement are restricted to the paid
Apple Developer Program ($99/year)** — a free "Personal Team" account cannot
enable either one in Xcode at all, for any backend. This isn't a CloudKit
quirk, it's a platform-wide rule: no app signed under a free account can ever
receive a real push notification, regardless of what sends it. Given a
straight choice between paying $99/year for true instant push-driven sync or
staying at literal $0 with best-effort sync, **$0 was chosen** — this
decision reshapes the architecture in §5.

Concretely, under the $0 rule as it now stands:

- **Backend**: Firebase (Firestore + Anonymous Authentication), **Spark
  (free) plan** — confirmed to require no credit card or billing account for
  Firestore and standard Authentication usage within free quotas (1 GiB
  storage, 50,000 reads/day, 20,000 writes/day — enormous headroom for two
  people). No CloudKit, no Cloud Functions (Cloud Functions now requires the
  paid Blaze plan / a linked billing account regardless of usage, so it's
  out entirely, not just for push).
- **No push notifications, anywhere.** Sync is realtime only while the app
  is in the foreground; otherwise it's best-effort on a refresh cadence
  controlled by iOS, not by us. See §5.4 for exactly what this means in
  practice — it's the central UX tradeoff of the whole $0 decision and
  should be read before designing any feature that assumes "the partner's
  phone will know right away."
- **Fonts/assets**: system fonts (e.g. SF Rounded) or open-license fonts
  only (e.g. Google Fonts / SIL Open Font License) — no paid type licenses.
- **Distribution**: no Apple Developer Program enrollment. Distribution path
  is installing directly to both partners' own devices via Xcode with a free
  Apple ID (free provisioning profiles), which requires re-installing/
  re-signing roughly every 7 days — and re-signing isn't remote-triggerable;
  it requires the developer's Mac and Xcode to reach the physical device
  again, over a cable or the same local network. **Decided**: accept this at
  $0 rather than pay for TestFlight distribution. The real, accepted
  consequence — not just "friction" — is that during any stretch longer
  than ~7 days where the partner's phone isn't near the developer's Mac
  (i.e. exactly the "apart" periods the app exists for), the app can stop
  launching until they're next physically together to reconnect it. There's
  no in-app way to warn about this (provisioning expiry isn't exposed to
  app code) — managing it is down to the developer's own external reminder,
  not a feature of the app. Re-sign opportunistically during every
  "together" window.
- **App Groups risk (flagged, not yet confirmed)**: the widget-sharing
  design in §6 leans on the App Groups capability to pass cached data
  between the app and widget extension. There are scattered developer
  reports of App Groups provisioning failing specifically under free
  Personal Team accounts ("communication with Apple failed" errors). Unlike
  the CloudKit/push finding, this one is *not* confirmed either way — it
  needs an early spike (create a trivial two-target project, free-team
  signed, and confirm App Groups provisions cleanly) before the widget
  architecture in §6 is finalized. A fallback that avoids App Groups
  entirely is noted there in case it doesn't work.
- **No paid third-party SDKs, analytics, crash reporting, or CI services.**

## 3. Goals / Non-Goals

**Goals (v1)**
- Live-ticking countdown widget (D/H/M/S) on Home Screen and Lock Screen.
- Both partners' apps/widgets reflect the same target date and status,
  subject to the sync latency realities in §5.4 (not instant unless both
  apps happen to be open).
- Simple two-state relationship status: `apart` ↔ `together`, toggled by
  either partner, synced to both devices.
- Manually-set "next meetup" date, editable by either partner.
- Append-only history log of together/apart events (see §7, Option A).
- Visually distinctive, polished UI (custom type, gradients, animated digit
  transitions).
- "Thinking of you" tap — a one-tap nudge that surfaces to the partner next
  time their app or widget refreshes; **not** an instant push (see §7.1 for
  the honest tradeoff this implies).
- Cumulative stats — total days together vs. apart over the relationship's
  lifetime, derived from the event log (see §7.2).
- Milestone celebration — a small in-app animation (e.g. confetti/haptic)
  when the countdown hits zero or a round-number milestone (see §7.3).
- Additional countdown types for anniversaries / other important dates,
  separate from the "next meetup" countdown (see §7.4).
- Partner time zone display — each partner's current local time/time zone
  shown alongside the countdown (see §9.1).

**Explicit non-goals for v1** (candidates for later)
- Auto-advancing scheduled calendar of future meetups (Option B, §7).
- Live Activity / Dynamic Island presence (also blocked by the no-push
  constraint for any *remote* updates to an already-started activity).
- Photo/note attachments on log entries.
- True instant, push-driven delivery of any kind — see §2 and §5.4. This is
  the biggest change from the v0.1 draft's assumptions and is now a
  permanent non-goal unless the $0 rule itself is revisited (see §10).
- **Accessibility (VoiceOver, Dynamic Type) and localization** — deliberate
  scope cuts, not oversights, worth naming explicitly rather than leaving
  silent: this is a private app for two known people who don't need either.
  Basic SwiftUI hygiene (using system text styles where practical) is free
  and fine to keep, but no dedicated accessibility or localization work is
  planned.

Rationale: ship the smallest version that proves the core loop (two phones,
one countdown, one toggle) before adding planning/journal features. Scope
creep is a real risk on a just-for-us app with no external deadline
pressure.

## 4. Corrected assumption

"Two different iPhone models" is not a real design constraint — a universal
SwiftUI app runs on any iPhone. The actual constraint is **minimum iOS
version**, since it gates which APIs are available:
- `Text(timerInterval:)` — iOS 15+
- Interactive widgets — iOS 17+ (not used in v1 anyway)

(Live Activities dropped from this list — see §3, it's a non-goal now that
remote updates to it would need push.)

**Resolved**: the two target devices are known (an iPhone 13 and a
MacBook Pro used for development), and iPhone 13 fully supports the current
latest iOS (confirmed against Apple's iOS 26 compatibility list — it
supports back to the iPhone 11 generation). Since this app only ever needs
to run on two specific, known phones rather than the general public, there's
no reason to target anything older than current. **Policy: minimum
deployment target = whatever the latest publicly released iOS is at the
time of building**, re-checked at build time rather than pinned to a number
now.

**Also previously unstated: iPhone only.** No iPad support/testing — this
app only ever runs on the two specific iPhones in question. If Xcode's
target defaults to a universal (iPhone+iPad) destination, restrict it to
the iPhone idiom explicitly rather than leaving an untested adaptive iPad
layout on the table.

The one place this could have been capped was the Mac side: Xcode 26
requires macOS Sequoia 15.6+ (later 26.x point releases require macOS Tahoe
26.2+). **Checked and closed**: the MacBook Pro is a 14-inch, Nov 2023,
Apple M3 — currently running Sonoma 14.6.1, but that's just because it
hasn't been updated yet, not a hardware ceiling. A 2023 Apple Silicon Mac
has years of macOS support ahead of it and will take Sequoia/Tahoe/whatever
comes next without issue. The only action item is a normal software update
before installing the latest Xcode — not a constraint on anything, just a
step in §13.

## 5. Architecture overview

```
┌──────────────┐                            ┌──────────────┐
│   Phone A     │                            │   Phone B     │
│  App+Widget   │                            │  App+Widget   │
└──────┬───────┘                            └──────┬───────┘
       │  read/write (SDK, foreground)              │
       │  read (REST, from widget)                  │
       └─────────────────┐        ┌──────────────────┘
                          ▼        ▼
                 ┌─────────────────────────┐
                 │  Firebase (Spark/free)   │
                 │  Firestore + Anonymous   │
                 │  Auth, no Cloud Functions│
                 │                          │
                 │  couples/{coupleId}:     │
                 │   status, nextMeetupDate,│
                 │   participantUIDs,       │
                 │   lastUpdatedBy/At       │
                 └─────────────────────────┘
```

No push in this diagram — deliberately. Both phones talk to the same
Firestore document, but nothing tells either phone *when* the other one
changed it. Freshness comes from four independent mechanisms layered
together (detailed in §5.2), each free, none of them push:

1. A live Firestore listener while the app is in the foreground (fast, but
   only while both apps happen to be open).
2. A fetch on every app launch/foreground transition (always fresh the
   moment you open the app).
3. A best-effort `BGAppRefreshTask` in the background (opportunistic, no
   guaranteed cadence, user-disableable).
4. The widget's own periodic OS-driven timeline refresh, which can do a
   lightweight fetch of its own each time it fires (frequency controlled by
   WidgetKit, not us).

Key point that's unchanged from v0.1: the countdown math itself still needs
no live connection — it's just `now - targetDate`, computed identically on
both devices once they agree on `targetDate`. What changed is that agreeing
on that value (and on `status`) is no longer instant by default.

### 5.1 Data model (v1) — Firestore

```
couples/{coupleId}                      // coupleId is the human-shareable join code
  - status: "apart" | "together"
  - nextMeetupDate: Timestamp?          // stored in UTC
  - participantUIDs: [String]           // Firebase Anonymous Auth UIDs, max 2
  - partnerProfiles: {                  // map keyed by uid
      [uid]: { displayName, timeZoneIdentifier }
    }
  - lastUpdatedBy: uid
  - lastUpdatedAt: Timestamp            // FieldValue.serverTimestamp()

couples/{coupleId}/events/{eventId}     // append-only, see §7 Option A
  - type: "became_together" | "became_apart"
  - timestamp: Timestamp
  - triggeredBy: uid
  // No TTL here, unlike pings below — this is intentional: cumulative
  // stats (§7.2) need the full history, and a lifetime of toggles for two
  // people is at most a few hundred documents, nowhere near a storage
  // concern (§5.7's free 1 GiB quota).

couples/{coupleId}/importantDates/{id}  // see §7.4
  - label: String
  - date: Timestamp                     // UTC
  - repeatsAnnually: Bool
  - createdBy: uid

couples/{coupleId}/pings/{pingId}       // "thinking of you", see §7.1
  - sentBy: uid
  - sentAt: Timestamp
  // TTL policy auto-deletes these after a few days, no Cloud Function
  // needed. (Verified: TTL is a Standard-edition Firestore feature, not
  // gated to Enterprise edition — a first search pass misread Firebase's
  // doc-site URL structure and suggested otherwise; a second pass found
  // Google's own docs explicitly describing TTL field behavior "for
  // Standard edition databases." High confidence, but cheap enough to
  // glance at in the console during §5.7's project setup to be certain.)
```

### 5.2 Sync flow (no push — four layered mechanisms)

1. **Foreground realtime listener**: `addSnapshotListener` on the couple
   document while the app is active. Near-instant (sub-second) updates as
   long as both apps are open and connected — this is the case that
   actually feels "instant," and it's a common real case (e.g. both
   partners open the app around the moment they're reuniting).
2. **Fetch on launch/foreground**: a one-shot `getDocument(source: .server)`
   the moment the app becomes active, before the listener attaches, so
   opening the app always shows the true current state immediately even if
   it's been closed for days.
3. **`BGAppRefreshTask`**: the main app schedules opportunistic background
   wake-ups (`BGTaskScheduler`, Background Modes → Background fetch — this
   does *not* require the paid Developer Program, only Push Notifications
   and iCloud do). iOS decides if/when it actually runs based on usage
   patterns and battery state, and the user can disable Background App
   Refresh globally in Settings. Treat this as a nice-to-have, not a
   guarantee.
4. **Widget's own refresh**: each time WidgetKit invokes the timeline
   provider (an OS-controlled cadence, not developer-controlled — no
   published minimum interval), the provider does a lightweight direct
   Firestore REST fetch (plain `URLSession` GET against
   `firestore.googleapis.com`, no SDK bundled into the extension to keep it
   under the widget's memory limit) and writes the result to the shared
   App Group cache before rendering. If App Groups turns out not to work
   under a free team (§2), the fallback is simpler: skip the shared cache
   and have the widget always do this REST fetch directly, with no
   dependency on the main app having run recently.
5. **Manual pull-to-refresh** in the main app as a zero-risk fallback,
   bound to a one-shot server fetch.

**Sync pipeline convention (previously unstated)**: any of the mechanisms
above that receives fresh server data — not just #4 — must write it to the
App Group cache and call `WidgetCenter.shared.reloadTimelines()`, not just
update in-memory UI state. Otherwise the widget only ever reflects mechanism
#4's own fetches, silently wasting the other three. Specifically: **the
partner who just took an action (toggled status, set a date) should see
their own widget update immediately**, driven locally by their own
successful write completing — this doesn't need network round-trips or the
OS's refresh budget at all, it's just "write succeeded → update cache →
reload timeline," fully within app control. Only the *other* partner's
widget is subject to the latency table in §5.4.

**Offline writes need no custom handling**: the Firestore SDK queues writes
made while offline and replays them automatically on reconnect — the app
target gets this for free by leaving the SDK's default persistence settings
alone. This does *not* extend to the widget's raw REST path (§5.5), which
has no queueing and relies entirely on the cache-fallback behavior already
specified there.

Conflict handling: last-write-wins by `lastUpdatedAt`
(`FieldValue.serverTimestamp()`), same as v0.1's design — Firestore server
timestamps make this trivial and it's still perfectly adequate for two
people.

**Quota headroom (sanity check, not exact)**: rough worst-case tally across
both devices — foreground listener attaches (~50/day), launch fetches
(~50/day), `BGAppRefreshTask` firings (~10/day, generously), and widget REST
fetches (assume a pessimistic ~70/day per widget instance, 2 instances per
device, 2 devices = ~280/day) — lands around 400-800 reads/day combined.
Firestore's free quota is 50,000 reads/day, so this is roughly 60-100x
headroom even under pessimistic assumptions. Not a concern at 2-user scale;
worth re-checking only if a bug ever causes a retry loop (§5.6 covers the
failure mode for that).

### 5.3 Pairing (no CKShare — join-code + Anonymous Auth)

1. Both apps call `Auth.auth().signInAnonymously()` on first launch,
   obtaining a stable per-install `uid` (free, part of Spark plan).
   **Caveat**: this identity is tied to the app install — deleting and
   reinstalling the app loses it, effectively unpairing that device. Worth
   deciding whether that's acceptable for v1 or needs a mitigation later
   (§10).
2. **Onboarding screen**: two clearly distinct, deliberate buttons — "Create
   a Pairing" and "Join a Pairing" — with copy that heads off the obvious
   failure mode: *"Only one of you should tap Create — have your partner
   tap Join with the code you'll get next."* If both partners mistakenly
   tap Create, the result is just two unused, unpaired couple docs — no
   corruption, and each self-cleans via the 48-hour TTL in step 6. Not
   worth a technical fix beyond clear copy. Before branching into
   Create/Join, ask for a display name (a single text field) — this is
   `partnerProfiles[uid].displayName` (§5.1), and it's the only onboarding
   input needed beyond the code itself.
3. **Partner A ("Create")**: app generates a random join code (6 chars,
   uppercase alphanumeric, ambiguous characters like `0`/`O`, `1`/`I`
   excluded) and creates `couples/{code}` with `participantUIDs: [uidA]`.
   The code *is* the document ID — no separate lookup/query needed.
   **Manually reading/typing the code out is the primary, required path.**
   Partner A can also share it via the native iOS share sheet (Messages,
   copy, etc.) and/or a locally-generated QR code (`CIFilter`'s
   `CIQRCodeGenerator`, built into CoreImage, free) as a convenience, but
   neither is guaranteed: a custom URL scheme
   (`couplecountdown://join/{code}`) scanned via the system Camera app
   behaves inconsistently across iOS versions and has no App Store fallback
   if the app isn't installed yet. Universal Links would fix that but need
   a hosted `apple-app-site-association` file (GitHub Pages would keep it
   $0, but it's a new moving part) — deferred out of v1; typing the code is
   what the flow is designed to always fall back to.
4. **Partner B ("Join")**: types the code (or uses the best-effort QR/deep
   link above). App fetches `couples/{code}`, and if
   `participantUIDs.size() < 2`, appends `uidB`.
5. **Security**: enforced entirely by Firestore Security Rules, no Cloud
   Function needed. Once a code is used to pair two participants, it stops
   granting access to anyone else — not just for joining, but for reading:

   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /couples/{coupleId} {
         // Readable only by an existing participant, or by anyone (i.e. a
         // holder of the code) while a slot is still open to join.
         allow get: if request.auth != null &&
           (request.auth.uid in resource.data.participantUIDs ||
            resource.data.participantUIDs.size() < 2);

         // No `list` is ever granted on this collection — codes can only
         // be looked up by exact ID, never browsed/enumerated.

         allow create: if request.auth != null &&
           request.resource.data.participantUIDs == [request.auth.uid];

         allow update: if request.auth != null && (
           // Existing participant editing anything EXCEPT participantUIDs
           // — membership can never be changed by a normal edit, only by
           // the join path below.
           (request.auth.uid in resource.data.participantUIDs &&
            !request.resource.data.diff(resource.data).affectedKeys()
              .hasAny(['participantUIDs']))
           ||
           // Joining: append self only, only while a slot is open, only
           // that one field changes.
           (resource.data.participantUIDs.size() < 2 &&
            !(request.auth.uid in resource.data.participantUIDs) &&
            request.resource.data.participantUIDs ==
              resource.data.participantUIDs.concat([request.auth.uid]) &&
            request.resource.data.diff(resource.data).affectedKeys()
              .hasOnly(['participantUIDs']))
         );

         allow delete: if false; // no deletes in v1

         // NOT `{sub=**}` (recursive wildcard) — that can match *zero*
         // additional segments in Firestore Rules, meaning it also
         // matched the couples/{coupleId} document itself and silently
         // granted any participant unrestricted write access there,
         // completely bypassing the tamper guard in `allow update` above.
         // Subcollections (events, importantDates, pings) are all exactly
         // one level deep, so requiring a mandatory collection-name
         // segment before the document wildcard is sufficient and
         // structurally can't match the parent.
         match /{subcollection}/{docId} {
           allow read, write: if request.auth != null &&
             request.auth.uid in
               get(/databases/$(database)/documents/couples/$(coupleId)).data.participantUIDs;
         }
       }
     }
   }
   ```

   **Verified — run against the Firestore emulator, 18/18 tests passing**
   (`firebase/test/rules.test.js`; run via `npm test` from `firebase/`),
   covering all five originally-planned cases (own participant edit, join
   while open, join while full, stranger read while full, membership
   tamper attempt) plus create/subcollection/unauthenticated-access checks.
   **This caught a real bug**, not a hypothetical one: the `{sub=**}` bug
   described above was found by the "membership tamper attempt" test
   failing against the first version of this file — pure inspection (mine
   and this document's, across two prior drafts) had missed it entirely.
   The fixed version above is what's actually in `firebase/firestore.rules`.
6. **Guessing-window mitigation**: at creation, set `codeExpiresAt: now +
   48h` on the couple doc and register it with a Firestore TTL policy
   (free on Spark, no Cloud Function — verified in §5.1). When the second
   participant joins,
   clear `codeExpiresAt` to `null` as part of that same write, so paired
   couples are never auto-deleted — only codes that sat unpaired for 2 days
   get cleaned up, which is what bounds how long a ~1-billion-combination
   code stays guessable at all.
7. Both devices persist `coupleId` locally (UserDefaults is fine — it's not
   secret on its own once paired) and from then on read/write the same
   document and subcollections via the standard Firestore SDK (app) or REST
   (widget, §5.2).

**Unpairing / reset — explicitly out of scope for v1.** There is no "leave"
or "delete" flow (the rules set `allow delete: if false`, §5.3 point 5
above). The only way to start over today is reinstalling the app, which
loses the old Anonymous Auth identity anyway (point 1) — the old couple doc
is simply abandoned, unused, and harmless at this data scale. Fine as a
known v1 limitation; not worth building a real reset flow until it's
actually needed.

### 5.4 Sync latency expectations — read this before designing UI copy

The honest cost of the $0 decision, spelled out:

| Scenario | Expected latency |
|---|---|
| Both partners have the app open | Near-instant (~1s), via the realtime listener |
| Partner's app is closed; they open it | Instant on open (launch fetch) |
| Partner's app is closed; they only glance at the widget | Whenever WidgetKit's own OS-controlled refresh next fires — could be minutes, could be hours; not something we control |
| Partner's phone is locked/idle, no interaction | No update at all until they check something — there is no proactive delivery, full stop |

Practically, this means the "thinking of you" tap and the together/apart
toggle behave less like a notification and more like a note left on a
fridge — real and synced, but seen whenever the other person happens to
look. Any UI copy or onboarding language should set that expectation rather
than implying real-time notification, to avoid the app feeling broken when
a ping doesn't arrive "instantly."

### 5.5 Widget authentication & failure-mode behavior

The gap in the original draft: §5.2 #4 says the widget does its own
Firestore REST fetch, but never said how it authenticates — the Security
Rules in §5.3 require `request.auth != null`, and a widget extension can't
reasonably bundle the full Firebase Auth SDK (memory budget).

**Decided design**: the main app, after signing in, persists the Anonymous
Auth **refresh token** (long-lived, unlike the 1-hour ID token) into a
Keychain access group shared with the widget extension. Before each REST
fetch, the widget mints its own short-lived ID token by POSTing the refresh
token to Google's token endpoint
(`https://securetoken.googleapis.com/v1/token?key=<FIREBASE_WEB_API_KEY>`,
`grant_type=refresh_token` — plain REST, no SDK), then attaches it as
`Authorization: Bearer <idToken>` on the Firestore REST GET. All of this is
plain `URLSession`, nothing bundled beyond what a widget extension can
afford.

**This depends on Keychain Sharing working under a free Personal Team** —
a separate capability from App Groups, and one that hasn't been checked
either. It should be verified in the same early spike as the App Groups
question (§10) rather than assumed.

**Failure-mode behavior (applies regardless of the above)**:
- The main app gets Firestore's SDK offline persistence for free (enabled
  by default) — it always has a last-known state to show even fully
  offline, no extra code needed.
- The widget's REST path has no such built-in cache. Its fetch must run
  with a short explicit timeout (~5s) and, on *any* failure — timeout, no
  network, expired/unrefreshable token, Keychain Sharing unavailable — fall
  back silently to the last value written to the App Group cache. The
  widget should never show an error state, only ever "last known good."

**All four App Groups × Keychain Sharing outcomes, planned individually**
(previously this only described two of them):
- **Both work**: design as-is above.
- **Only Keychain Sharing works**: store `coupleId` in the shared Keychain
  alongside the refresh token (a Keychain item can hold any string, not
  just the token) and skip the App Group cache entirely — the widget
  becomes fully self-sufficient via Keychain + REST, no App Groups
  dependency anywhere.
- **Only App Groups works**: the widget can't mint its own ID token, so
  mechanism #4 in §5.2 degrades to "off" — the widget only ever shows what
  the main app last wrote to the cache, no independent refresh.
- **Neither works**: this is the case previously undersold as "not a dead
  end, just staler" — without either capability the widget has no
  automatic channel to receive *any* data, which would break the countdown
  display entirely, not just make it stale. The real fallback is making
  the widget a **configurable widget** (`AppIntent`/`IntentConfiguration`)
  where `coupleId` (and a long-lived custom token, separate from Firebase
  Auth) is entered manually into the widget's own settings when it's added
  to the Home Screen — WidgetKit persists configuration values itself,
  independent of App Groups or Keychain. Real UX friction (manual
  copy/paste once), but a genuine escape hatch rather than a dead end.

### 5.6 Project & target structure

Not previously specified. Concretely:

- **`CoupleCountdown`** — main app target. Owns all Firebase SDK usage
  (Firestore, Auth) via Swift Package Manager. Owns onboarding/pairing UI,
  the main countdown screen, stats, settings.
- **`CoupleCountdownWidget`** — WidgetKit extension target. No Firebase SDK
  dependency at all — only `URLSession` for its own REST fetch (§5.5) and
  reads/writes to the App Group cache. Kept deliberately thin to stay
  inside the extension's memory ceiling.
- **`CoupleCountdownKit`** — a local Swift Package, depended on by both
  targets, holding backend-agnostic shared code: the data models (§5.1),
  the App Group cache read/write helpers, and date/countdown formatting
  logic. Firebase-SDK-specific code (the app's `FirestoreService`) stays in
  the app target, not this package, so the widget target never risks
  pulling in the SDK transitively.
- **Capabilities needed**: App Groups (app + widget), Keychain Sharing (app
  + widget), Background Modes → Background fetch (app only). None of these
  are on Apple's paid-only capability list the way iCloud/Push are (§2),
  but the App Groups and Keychain Sharing entries are still flagged as
  needing empirical confirmation under a free team (§10).

### 5.7 Firebase project setup

Not previously specified, and two of these choices are irreversible once
made:

- **Firestore mode**: must be **Native mode**, not Datastore mode — Native
  is the only mode the mobile client SDKs support. Easy mistake to make at
  project creation since the console offers both; worth double-checking
  before clicking through.
- **Region**: irreversible once set. Pick whichever Firestore region is
  closest to wherever the app will actually be used day-to-day, not
  necessarily the default suggestion.
- **Authentication**: enable the Anonymous provider only — no email/
  password, no SMS (SMS verification requires the paid Blaze plan per §2).
- **App Check**: not enabled in v1 (§10) — can be added later without a
  data-model change.

### 5.8 Implementation conventions (previously unstated)

- **Concurrency**: Swift structured concurrency (`async`/`await`)
  throughout — the Firebase iOS SDK supports it natively, no
  completion-handler-style wrapping needed.
- **Cold-launch loading state**: on a fresh launch, Firebase Auth/Firestore
  SDK initialization and the launch fetch (§5.2 #2) aren't instant — the
  main countdown screen needs a brief loading state (a simple spinner/
  placeholder is enough) rather than either blocking on a splash screen or
  flashing an empty/zero countdown before real data arrives.

## 6. Widget design

- **Home Screen widget**: WidgetKit extension, small/medium/large families.
  Countdown rendered via `Text(timerInterval:countsDown:)` so the OS ticks
  it without background execution — this part is completely unaffected by
  the backend change.
- **Lock Screen widget**: same extension, add `.accessoryCircular` /
  `.accessoryRectangular` / `.accessoryInline` families.
- **Data source**: primarily the shared App Group cache (§5.2, #4), written
  by the main app whenever it runs and refreshed by the widget's own REST
  fetch on each OS-driven timeline reload (auth mechanism in §5.5).
  **Contingent on the App Groups risk flagged in §2** — if that capability
  doesn't provision cleanly under a free team, drop the shared cache and
  have the widget always fetch directly via REST instead; slightly less
  efficient, no architectural dead end either way.
- **First-run empty state**: if the widget is added before pairing (§5.3)
  completes, there's no `coupleId` yet to fetch anything with — it should
  show a simple "Not paired yet" placeholder (WidgetKit's placeholder/
  snapshot content) that deep-links into the app's onboarding screen when
  tapped, rather than an error or blank state.
- **No-date-set state applies immediately after pairing, too**: a freshly
  created couple doc starts with `nextMeetupDate: null` (§5.1) — so the
  "prompt to enter a date" behavior described for the "leaving again with
  no date" edge case (§8) is really the same empty state, and should reuse
  the same UI component rather than being built as two separate flows.
- **Live Activity**: removed from scope — see §3, remote updates would
  require push.
- **Deep link**: widget tap opens the app to the main countdown screen.
  Cheap, wire in from the start.
- **Timeline provider entries/policy (previously unstated)**: `getTimeline`
  should return a **single** entry — `Text(timerInterval:)` handles the
  digit ticking on its own, so there's no need to pre-generate a series of
  future entries the way a typical numeric countdown widget would. Use
  `Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30
  * 60)))` (roughly 30 minutes out) rather than `.never` (would starve
  updates entirely) or `.atEnd` (with only one entry, this can trigger an
  immediate re-request and risk hammering the refresh budget). The 30-minute
  ask is a request, not a guarantee — WidgetKit's actual cadence is still
  OS-controlled per §5.2 #4, this just states the intent explicitly instead
  of leaving it to whatever the default would have been.

## 7. Calendar / logging — options

- **Option A — history log (v1 choice)**: every together/apart toggle is
  timestamped and stored as an event; rendered as a simple log or calendar
  view. Pure append-only CRUD, no effect on countdown logic.
- **Option B — forward planning calendar** (deferred): couple pre-schedules
  future meetup date ranges; countdown auto-advances to the next scheduled
  date after a "leaving again" tap instead of requiring manual re-entry.
  Needs a proper `[MeetupEvent]` model with start/end dates.
- **Option C — both** (long-term direction): most compelling end state, but
  not v1. Revisit once A is shipped and validated.

### 7.1 "Thinking of you" tap

A single button, independent of the together/apart status, that writes a
`pings/{pingId}` document (§5.1). **Important change from v0.1**: this was
originally framed as "purely upside" because it was assumed to ride on push
infrastructure that turned out not to be available at $0 (§2). Without push,
a ping only surfaces per the latency table in §5.4 — it will *not* buzz the
partner's phone the moment it's sent unless their app happens to be open.
Still cheap to build and still a nice touch, just not the same feature it
would be with push. Worth being explicit about this in the app's own copy
(§5.4) so it doesn't read as a bug.

`ThinkingOfYouPing`/`pings` records use a Firestore TTL policy to
auto-expire after a few days — free on the Spark plan, no cleanup job
needed. They're intentionally not written into the permanent
`RelationshipEvent`/`events` history (§7) — a nudge isn't a milestone.

### 7.2 Cumulative stats

Derived, not stored: compute total days `together` and total days `apart`
by walking the `events` subcollection (§5.1) and summing the durations
between consecutive status changes. Purely client-side computation over
data already being kept for Option A — no schema or sync changes. Backend
change from v0.1 doesn't affect this feature at all.

### 7.3 Milestone celebration

A local, client-side-only animation (confetti, haptic, or similar) fired
when:
- the countdown reaches zero (the meetup date arrives), or
- a round-number milestone is crossed (e.g. 100 days together, 1 year since
  first log entry).

Still purely a client check against whatever data is currently cached/
synced — unaffected by backend choice, but worth noting one consequence of
§5.4: without push, this check only runs when the app/widget happens to
refresh, so a milestone could in principle be detected a bit "late" (e.g.
the countdown hits zero while the phone is asleep, celebration fires next
time it's checked) rather than at the exact instant. Not worth engineering
around for v1.

### 7.4 Anniversary / important-date counters (separate countdown type)

In addition to the "next meetup" countdown, support a small list of
independent countdowns backed by `importantDates` (§5.1) — e.g. relationship
anniversary, a wedding date, a first-met date. Each behaves like its own
mini version of the core countdown:
- Manually entered by either partner, synced via the same Firestore
  document tree.
- `repeatsAnnually` flag lets an anniversary silently roll forward to next
  year once it passes, rather than counting into negative days.
- Surfaced in-app as a list, and optionally as an additional widget/Lock
  Screen accessory a user can choose to pin alongside (or instead of) the
  "next meetup" countdown.
- Deliberately kept separate from `couples/{coupleId}`'s `status`/
  `nextMeetupDate` — these are informational countdowns, not tied to the
  apart/together state machine (§8), so they don't interact with that logic
  at all.

## 8. State machine

```
[APART] --tap "We're together"--> [TOGETHER]
[TOGETHER] --tap "Leaving again"--> [APART]
```

Edge cases to handle explicitly:
- "Leaving again" tapped with no future date set → prompt to enter one;
  never silently show a null/broken countdown.
- Near-simultaneous conflicting taps from both partners → resolved by
  server-timestamp last-write-wins (§5.2); no special UI. Slightly more
  likely to matter now than under push-driven sync, since without a live
  listener neither partner necessarily sees the other's tap before making
  their own — still fine to resolve silently for two people.

**Write atomicity (previously unstated)**: a status toggle touches two
places at once — the `couples/{coupleId}` document (`status`,
`lastUpdatedBy`, `lastUpdatedAt`) and a new `events/{eventId}` append
(§5.1). These must be committed as a single Firestore `WriteBatch`, not two
separate calls — otherwise a dropped connection between the two writes
could leave the current status and the history log disagreeing about what
happened. Cheap to get right up front, easy to overlook.

## 9. Visual design direction

- Custom display numeral font for the countdown digits (rounded or serif,
  not system default) for a premium feel — must be a system font (e.g. SF
  Rounded) or an open-license font per the $0 rule in §2, no paid type
  licenses.
- Soft gradients; `contentTransition(.numericText())` (iOS 16+) for animated
  digit rolling on tick.
- Per-couple theme (color/gradient enum), selectable by either partner,
  shared via the same backend record.
- SwiftUI is sufficient for all of this — no custom rendering engine needed.
  This is craft/time cost, not architectural risk.
- **Dark mode (previously unstated)**: system fonts/colors handle
  light/dark automatically, but the custom gradient theme (§9, per-couple
  color choice) doesn't get that for free — each theme option needs its
  contrast/legibility checked in both appearances before it ships, not just
  designed against one.

### 9.1 Partner time zone display

Show each partner's current local time and time zone alongside the
countdown (e.g. "Her: 9:14 PM CDT · Him: 3:14 AM CET"). This is the feature
**least affected** by the backend/push change — a time zone identifier
changes rarely (only when someone travels), so even best-effort sync (§5.4)
keeps this accurate in practice almost all the time.

- Backed by `partnerProfiles[uid].timeZoneIdentifier` (§5.1), refreshed from
  `TimeZone.current.identifier` on each app launch and written back to
  Firestore like any other field.
- Display-only: does not change how `nextMeetupDate` is stored (still UTC)
  or how the countdown itself is computed — only how the *current time*
  readout is formatted per partner.
- Reasonable v1 surface: main app screen. A widget variant showing both
  local times is a natural but non-essential follow-on.

## 10. Open questions

**Genuinely open — need your input or empirical testing, not yet resolved:**

- **App Groups, Keychain Sharing, *and* Background Modes under a free
  Personal Team**: broadened from two capabilities to three — verification
  found that `UIBackgroundModes` is fundamentally an `Info.plist` key, not
  an entitlement (supporting the original claim that it's free-team safe),
  but also surfaced scattered free-team users reporting Xcode's Capabilities
  UI adding it as an entitlement anyway and then failing to provision. That
  puts Background Modes in the same uncertain bucket as App Groups/Keychain
  Sharing rather than a separately-settled one. **Resolution plan**: one
  spike covering all three — a throwaway two/three-target project,
  free-team signed, confirming each provisions without error. All three
  already have documented fallbacks (§5.5/§6 for the first two; §5.2 #3 is
  already framed as "nice-to-have, not guaranteed" for the third), so a
  failure here degrades the app, it doesn't block the project — see §5.5's
  four-outcome fallback tree for exactly how App Groups/Keychain Sharing
  failures are handled.
- **`BGAppRefreshTask` real-world reliability**: needs empirical testing on
  a real device over a few days to understand actual firing frequency.
  **Pre-committed threshold**: instrument every firing (timestamp appended
  to a small persisted log, §5.8) from day one of having the app running,
  and if real-world data shows meaningfully fewer than ~2 firings/day on
  average, drop the mechanism from v1 rather than keep maintaining code for
  a path that isn't pulling its weight — mechanisms #1/#2/#4 already cover
  the important cases without it.
- **Revisiting the $0 rule later**: if the best-effort sync in §5.4, or the
  re-signing consequence in §2, prove too painful in practice once actually
  used, the $99/year path (CloudKit + push, and/or TestFlight distribution,
  as drafted in v0.1/discussed in §2) remains a known, fully-designed
  fallback — worth keeping this document's v0.1 CloudKit sections in git
  history rather than deleting the thinking, in case that tradeoff gets
  revisited. **Make the trigger measurable, not a vibe**: extend the same
  `BGAppRefreshTask` instrumentation above to also log real sync latency —
  timestamp when a partner made a change vs. when it was actually observed
  on the other device — so this decision has real data behind it later
  instead of "it felt slow."

**Fully resolved:**

- **Minimum iOS version / MacBook Pro macOS ceiling** (§4): closed — target
  latest publicly released iOS as a standing policy, and the Nov 2023 M3
  MacBook Pro has no hardware ceiling on macOS/Xcode versions, just needs a
  routine software update (Sonoma 14.6.1 → Sequoia/Tahoe) before installing
  the latest Xcode.
- **Firestore Security Rules** (§5.3): written, run against the local
  emulator, 18/18 tests passing (`firebase/test/rules.test.js`) — this
  needed no Apple hardware at all, so it was done ahead of the
  device-bound items above rather than waiting on them. Found and fixed a
  real bug in the process (the `{sub=**}` recursive-wildcard issue
  documented in §5.3), not just a hypothetical one — direct evidence that
  the emulator-testing step was worth doing rather than trusting inspection
  alone, and a useful data point for how much scrutiny the remaining
  untested pieces of this design still deserve.

**Decided with a default — documented, but flag if you'd rather change
them:**

- **Distribution re-signing** (§2): accepted at $0 — the app can go dark on
  the partner's phone during long "apart" stretches until next physically
  reunited with the developer's Mac.
- **Widget authentication**: Keychain-shared refresh token + REST token
  minting (§5.5), degrading gracefully to cache-only if Keychain Sharing
  turns out not to work under a free team.
- **QR/deep-link pairing**: best-effort convenience only; manually
  typing/reading the code is the primary, required path (§5.3). No
  Universal Links in v1 (would need external hosting for the AASA file).
- **Anonymous Auth identity loss on reinstall** (§5.3): accepted as a known
  v1 limitation — no "recovery code" mechanism built for it. Cheap to add
  later if it becomes a real pain point, not worth the complexity now.
- **Unpairing/reset**: out of scope for v1 (§5.3) — reinstalling is the
  only reset path, and it already loses the Anonymous Auth identity per the
  point above, so there's no separate mechanism needed.
- **Firebase App Check** (free, DeviceCheck/App Attest-based): not in v1
  (§5.7) — the 48-hour code TTL (§5.3) is judged sufficient hardening for a
  2-person app for now. App Check would shut down automated code-guessing
  entirely rather than just bounding its window, and can be added later
  without any data-model change if it ever seems worth it.

## 11. Suggested future features (not committed)

- Photo/note attached to each together/apart log entry (journal-ification
  of the log — low incremental cost, builds on Option A's event
  subcollection).
- Local notification N days before the next meetup date — this one *is*
  still $0-compatible even without push, since it's a purely local
  `UNUserNotificationCenter` schedule off a date already on-device, not a
  remote-triggered notification.
- Revisit paid Apple Developer Program ($99/year) for true push-driven sync
  if the latency in §5.4 turns out to matter more than expected in real use
  (see §10).

## 12. Rough scope estimate

The backend swap changes where the effort goes, not really how much there
is. CloudKit sharing (v0.1) would have offloaded pairing/sharing/push to
Apple's infrastructure almost for free, engineering-wise. The $0-compliant
Firestore design (v0.2) trades that for: writing and testing real Security
Rules by hand (§10), building the join-code pairing flow from scratch
(§5.3), and building the widget's own token-refresh + REST-fetch path
(§5.2) instead of getting push for free. None of this is exotic, but it's
more custom code than the CKShare path would have needed. For a developer
experienced with SwiftUI but new to Firestore + WidgetKit: still roughly
one to two weeks solo, similar to the v0.1 estimate, with the risk
concentrated in the security-rules and widget-REST-fetch pieces rather than
in push/pairing plumbing.

## 13. Next steps

1. Spike the App Groups + Keychain Sharing + Background Modes-under-free-
   team question (§10) — quick, and gates the widget architecture in §6,
   the widget auth design in §5.5, and how much to trust `BGAppRefreshTask`
   in §5.2 #3.
2. Update the MacBook Pro past Sonoma 14.6.1 to Sequoia/Tahoe (§4) before
   installing the latest Xcode — routine, no longer an open question.
3. Set up the Xcode project with the target structure from §5.6.
4. ~~Write/test the Security Rules from §5.3 using the local emulator~~ —
   **done** (§10). Still need to set up the real Firebase project itself
   per §5.7 (Spark plan, Native-mode Firestore, Anonymous Auth only) —
   that half needs your Google login and hasn't happened yet.
5. Build the join-code pairing flow (§5.3) end to end between two test
   devices/accounts, including the onboarding name-entry step.
6. Build the sync mechanisms (§5.2) incrementally: launch fetch first
   (simplest, highest value), then the foreground listener, then the
   widget's own REST fetch + token refresh (§5.5), then `BGAppRefreshTask`
   last (lowest reliability, least urgent).
7. Confirm v1 feature scope unchanged from §3: core countdown + status
   toggle + history log + thinking-of-you tap + cumulative stats +
   milestone celebration + anniversary counters + partner time zone
   display — now with the shared understanding that none of it is
   push-instant (§5.4), and that distribution itself has the re-signing
   limitation accepted in §2.
8. Design a real AppIcon asset before the first install to a home screen —
   easy to forget since a default/blank icon doesn't block a build, but
   looks broken once it's actually sitting on a phone.
