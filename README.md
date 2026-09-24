# CoupleCountdown

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Web-lightgrey)
![Swift](https://img.shields.io/badge/UI-SwiftUI%20%2B%20WidgetKit-orange)
![Backend](https://img.shields.io/badge/backend-Firebase%20Firestore-yellow)
![Status](https://img.shields.io/badge/status-working-brightgreen)
![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red)

An app for couples in long-distance relationships: a shared, synced
countdown to their next visit, a shared calendar of planned visits and
important dates, and a two-state "apart / together" toggle either partner
can update. It runs as a native iPhone app with Home Screen and Lock Screen
widgets, and as a web app for computers and any other phone. Both work from
the same account and data.

## Status

**Implemented and working.** The project includes:

- a SwiftUI iPhone app with a WidgetKit extension;
- a web client;
- a real Firebase backend;
- a CI pipeline that builds, tests, and publishes an installable build on
  every push (see [Use it](#use-it) below).

The CI runs these tests on every push:

- 14 XCUITest UI tests against the live backend;
- 19 unit tests;
- 29 Security Rules tests;
- the web client's date logic, checked in five time zones.

The full architecture, decisions, and rationale live in
[`DESIGN.md`](DESIGN.md), and its §0 summarizes the current state.

Not yet verified: installing on a physical iPhone. CI builds the
real-device app, but the widget's data sharing under free Apple ID signing
has only been exercised in the Simulator so far. See
[Known gaps](#known-gaps).

## Use it

**On the web — any phone, tablet, or computer, nothing to install:**
**<https://couplecountdown-7715c.web.app>**. On a phone, use Share → *Add to
Home Screen* for an app-style icon. The web version has the core
experience: pairing, the live countdown, apart/together, the calendar of
visits and important dates, stats, and themes. It syncs with the iPhone app
through the same backend and join codes, but as a website it can't provide
a Home Screen or Lock Screen widget.

**On iPhone, with the widget:** no Apple Developer account, no App Store,
and no cloning this repo. Install it with [SideStore](https://sidestore.io),
a free sideloading tool that signs apps with your own Apple ID.

1. Set up SideStore on the iPhone by following
   [its install guide](https://docs.sidestore.io).
2. In SideStore, open **Sources**, tap **+**, and add:
   `https://github.com/Phillyfanbert/CoupleCountdown/releases/download/latest/source.json`
3. Install **CoupleCountdown** from that source. SideStore offers updates
   from it whenever a new build is published.
4. Add the widget: long-press the Home Screen, tap **+** (or **Edit → Add
   Widget**), and choose **CoupleCountdown**.

Alternatively, download
[`CoupleCountdown.ipa`](https://github.com/Phillyfanbert/CoupleCountdown/releases/download/latest/CoupleCountdown.ipa)
and open it with SideStore. Both links point at a rolling release that CI
rebuilds on every push to `main`, so they never go stale. An app signed with
a free Apple ID has to be refreshed every 7 days, and SideStore does that on
the phone itself.

**Accounts:** sign up once with an email and password, then sign in with
the same account on as many devices as you like: the iPhone app, your
phone's browser, your computer. Every one shows the same countdown. Your
partner makes their own account and joins with your code. A pairing is
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

## Features

- **Live countdown to the next visit** to the minute you actually meet,
  not just the day. It ticks in the app, on the web, and in iPhone Home
  Screen and Lock Screen widgets.
- **Shared calendar:** plan any number of visits, each with a date, a time,
  and an optional note, and see them on a month grid. The countdown and
  widget always follow the next planned visit, so tapping "Leaving again"
  switches straight to it.
- **Important dates** (anniversaries, birthdays), optionally yearly, with
  "Today" / "in N days" countdowns. A date shows as the same day for both
  partners, whatever their time zones.
- **Apart / together toggle**, synced between both partners, with every
  change recorded in an append-only history log.
- **Stats:** total days together and apart, derived from that log.
- **Each partner's current local time** alongside the countdown.
- **Milestone celebrations** when a countdown reaches zero or a round
  number of days together (iPhone app).
- **Themes** with light and dark variants.
- **Email + password accounts:** one account works on all your devices. No
  phone numbers, no Apple ID requirement.

### Known gaps

- **"Thinking of you"** nudges are sent and stored, but neither app shows
  received ones yet, so for now the partner never sees them.
- **Join codes don't expire yet.** The app records a 48-hour expiry, but
  nothing enforces it: there's no Firestore TTL policy configured and no
  rules check. A code stops working once your partner joins or you cancel
  it.
- **No push notifications, by design:** they'd need the paid Apple
  Developer Program. A partner's change shows up when the other person
  opens the app or the widget next refreshes.
- **Themes are per device**, not shared between partners.
- **The web app** has no widget, which a website can't provide, and no
  milestone celebrations.
- **Real-device install** hasn't been confirmed on a physical iPhone yet
  (see [Status](#status)).

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
  design doc). The same rule shaped distribution: no Mac with Xcode is
  needed at all. GitHub Actions builds and tests every push and publishes
  the installable app.
- **Hand-written Firestore Security Rules as the entire security model.**
  There's no server and no Cloud Functions, which the $0 constraint also
  excludes. Pairing and access control are enforced entirely by declarative
  rules, including:
  - an append-only membership rule for two-person pairing;
  - a field-level tamper guard;
  - owner-only account records;
  - a rule that a pairing can be cancelled only before the partner has
    joined, which closes a race a code review found.

  The rules are tested against the Firestore emulator in CI.
- **A widget architecture that doesn't assume its host app is running.**
  The WidgetKit extension performs its own authenticated network fetch
  independently of the main app, with a fully-specified fallback chain for
  every combination of iOS capability availability under free-tier code
  signing.
- **Dates that mean the same day everywhere.** A long-distance couple is
  usually in two time zones. An anniversary is stored as a calendar day
  rather than an instant, so it reads as the same day for both partners. A
  naive encoding showed it a day early to the partner further west. The
  web logic tests run in five time zones in CI to keep it that way.
- **Every open technical question resolved to a decision tree, not left
  vague.** Where a question couldn't be answered by design alone (e.g.
  whether a given entitlement provisions cleanly under free-tier signing),
  the plan specifies the exact test, both possible outcomes, and the
  pre-committed action for each — so implementation never stalls waiting
  on a judgment call.

## Tech stack

- **UI:** SwiftUI and WidgetKit (Home Screen and Lock Screen widgets) on
  iPhone. On the web, a dependency-free static client (`web/`) hosted on
  Firebase Hosting's free tier.
- **Backend:** Firebase Firestore (free Spark plan) and Firebase
  Authentication (email + password accounts, shared by the iPhone app and
  the web client).
- **Sync:** no push notifications. A layered, honestly-documented
  best-effort sync strategy: a realtime listener, a fetch on launch,
  background refresh, and independent widget refresh.
- **Security:** Firestore Security Rules, hand-written and tested against
  the local emulator.
- **CI:** GitHub Actions. It generates the Xcode project with XcodeGen,
  builds, runs the unit, UI, rules, and web tests, and publishes the
  installable build.
- **Distribution:** an unsigned `.ipa` installed through SideStore with a
  free Apple ID, with no paid Developer Program. The web app is on Firebase
  Hosting.

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
