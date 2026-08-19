# CoupleCountdown

![Platform](https://img.shields.io/badge/platform-iOS-lightgrey)
![Swift](https://img.shields.io/badge/UI-SwiftUI%20%2B%20WidgetKit-orange)
![Backend](https://img.shields.io/badge/backend-Firebase%20Firestore-yellow)
![Status](https://img.shields.io/badge/status-in%20design-blue)
![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red)

A native iOS app for couples in long-distance relationships: a shared,
synced countdown to their next time together, live on the Home Screen and
Lock Screen, with a two-state "apart / together" toggle either partner can
update from their own phone.

## Status

**In design — not yet implemented.** This repository currently holds a
complete architecture and implementation plan, refined through iterative
review, technical verification, and explicit tradeoff decisions. Source
code will follow. See [`DESIGN.md`](DESIGN.md) for the full design
document.

## Why this project

Countdown-to-reunion apps for long-distance couples are a real, small
niche (see: Timestamp, Tondr, Lasting) — this is my own take on it, built
as both a genuine tool for personal use and an exercise in working through
a full mobile app design under a real constraint: it had to cost **exactly
$0** to build and run, indefinitely, with no exceptions. That single
constraint ended up shaping almost every architectural decision in the
project — see [Notable engineering decisions](#notable-engineering-decisions)
below.

## Planned features

- Live-ticking countdown widget (days/hours/minutes/seconds) on the Home
  Screen and Lock Screen
- Two-state relationship status (`apart` ↔ `together`) synced between both
  partners' devices
- A lightweight join-code pairing flow — no accounts, no phone numbers
- Append-only history log of together/apart events, with derived cumulative
  stats (total days together vs. apart)
- A "thinking of you" one-tap nudge
- Milestone celebrations (countdown hitting zero, round-number day counts)
- Separate countdown types for anniversaries and other important dates
- Each partner's current local time/time zone shown alongside the countdown

## Notable engineering decisions

A few things worth a recruiter's second look, beyond "it's a countdown
app":

- **A hard $0 cost constraint, taken literally.** Both the iCloud/CloudKit
  capability and the Push Notifications entitlement turned out to require
  Apple's paid $99/year Developer Program — a fact that broke the original
  CloudKit-based architecture partway through design. Rather than quietly
  paying for it, the whole sync model was redesigned around Firebase's free
  tier and **no push notifications at all**, with an honest, explicit
  accounting of exactly what that costs in sync latency (see §5.4 of the
  design doc).
- **Hand-written Firestore Security Rules as the entire security model.**
  With no server and no Cloud Functions (also excluded by the $0
  constraint), pairing and access control are enforced entirely by
  declarative rules — including an append-only membership rule for
  two-person pairing, a field-level tamper guard, and a TTL-based
  brute-force mitigation on join codes.
- **A widget architecture that doesn't assume its host app is running.**
  The WidgetKit extension performs its own authenticated network fetch
  independently of the main app, with a fully-specified fallback chain for
  every combination of iOS capability availability under free-tier code
  signing.
- **Every open technical question resolved to a decision tree, not left
  vague.** Where a question couldn't be answered by design alone (e.g.
  whether a given entitlement provisions cleanly under free-tier signing),
  the plan specifies the exact test, both possible outcomes, and the
  pre-committed action for each — so implementation never stalls waiting
  on a judgment call.

## Tech stack

- **UI**: SwiftUI, WidgetKit (Home Screen + Lock Screen widgets)
- **Backend**: Firebase Firestore (free Spark plan) + Firebase Anonymous
  Authentication
- **Sync**: no push notifications — a layered, honestly-documented
  best-effort sync strategy (realtime listener, launch fetch, background
  refresh, and independent widget refresh)
- **Security**: Firestore Security Rules (hand-written and tested against
  the local emulator)
- **Distribution**: free Apple ID code signing — no paid Developer Program

## Documentation

The full design document — architecture, data model, security rules,
pairing flow, sync strategy, open questions, and rationale for every major
decision — lives in [`DESIGN.md`](DESIGN.md).

## License

All rights reserved. This repository is public for portfolio/viewing
purposes only — no permission is granted to use, copy, modify, or
distribute this code or any part of this project. See
[`LICENSE`](LICENSE) for the full notice.

## Author

**Philbert Fan**
