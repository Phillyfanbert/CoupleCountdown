# CoupleCountdown

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Web-lightgrey)
![Swift](https://img.shields.io/badge/UI-SwiftUI%20%2B%20WidgetKit-orange)
![Backend](https://img.shields.io/badge/backend-Firebase%20Firestore-yellow)
![Status](https://img.shields.io/badge/status-working-brightgreen)
![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red)

A native iOS app for couples in long-distance relationships: a shared,
synced countdown to their next time together, live on the Home Screen and
Lock Screen, with a two-state "apart / together" toggle either partner can
update from their own phone.

## Status

**Implemented and working.** SwiftUI app + WidgetKit extension, a real
Firebase backend, an XCUITest suite exercising every feature against that
live backend, and a CI pipeline that builds, tests, and publishes an
installable build on every push — see
[Use it](#use-it) below. The full
architecture, decisions, and rationale live in [`DESIGN.md`](DESIGN.md).

## Use it

**On the web — any phone, tablet, or computer, nothing to install:**
**<https://couplecountdown-7715c.web.app>**. On a phone, use Share → *Add to
Home Screen* for an app-style icon. The web version has the full core
experience (pairing, live countdown, apart/together, important dates, stats,
"thinking of you", themes) and syncs with the iPhone app through the same
backend and join codes — but, as a website, it can't provide a Home Screen
or Lock Screen widget.

**On iPhone, with the widget:** no Apple Developer account, no App Store,
no cloning this repo — install via [SideStore](https://sidestore.io), a free
sideloading tool.

👉 **[Install CoupleCountdown](https://claude.ai/code/artifact/9ed9d819-165c-4b3b-a503-950ad8e4c809)** —
open this on the iPhone you want it on. It has one-tap install/update
links (GitHub strips custom app links like `sidestore://` from rendered
Markdown, which is why they're on that page instead of directly here) and
a link to SideStore's own setup guide if you don't have SideStore yet.
Both links on that page point at a rolling release that's rebuilt
automatically on every push to `main`, so they never go stale.

**Accounts:** sign up once with an email and password, then sign in with
the same account on as many devices as you like — the iPhone app, your
phone's browser, your computer — and every one shows the same countdown.
Your partner makes their own account and joins with your code. A pairing is
always exactly two people, but each of you can use any number of devices.

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
- A lightweight join-code pairing flow on top of simple email + password
  accounts — one account works on all your devices; no phone numbers
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

- **UI**: SwiftUI, WidgetKit (Home Screen + Lock Screen widgets) on iPhone;
  a dependency-free static web client (`web/`) hosted on Firebase Hosting's
  free tier
- **Backend**: Firebase Firestore (free Spark plan) + Firebase
  Authentication (email + password accounts, shared by the iPhone app and
  the web client)
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
