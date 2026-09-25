// Mirrors CoupleCountdownKitTests.swift so the web port can't drift from the
// iPhone app's behavior. Run: node --test web/logic.test.js
// Run under several time zones in CI (TZ=...) — the calendar-day tests are
// exactly about behaving the same everywhere.
import test from "node:test";
import assert from "node:assert/strict";
import {
  addDays,
  computeStats,
  countdownParts,
  dayFromStored,
  daysUntil,
  durationLabel,
  formatStatDays,
  defaultVisitStart,
  localISODate,
  monthCells,
  nextOccurrence,
  nextUpcoming,
  normalizedStart,
  parseLocalISODate,
  pingHeadline,
  relativeDayLabel,
  resolvedNextMeetup,
  reunionMessage,
  separations,
  storedFromLocalDay,
  timeAgo,
  unseenPings,
  visitMetEarly,
  zonedTime,
} from "./logic.js";

const DAY = 86_400_000;
const ymd = (d) => [d.getFullYear(), d.getMonth() + 1, d.getDate()];

test("empty events produce zero stats", () => {
  assert.deepEqual(computeStats([]), { totalDaysTogether: 0, totalDaysApart: 0 });
});

test("stats sum the span between consecutive events (same case as the Swift test)", () => {
  const start = new Date(0);
  const events = [
    { type: "became_together", timestamp: start },
    { type: "became_apart", timestamp: new Date(5 * DAY) },
    { type: "became_together", timestamp: new Date(15 * DAY) },
  ];
  const s = computeStats(events, new Date(20 * DAY));
  assert.ok(Math.abs(s.totalDaysTogether - 10) < 1e-4);
  assert.ok(Math.abs(s.totalDaysApart - 10) < 1e-4);
});

test("events with a pending (null) timestamp are ignored", () => {
  const s = computeStats([{ type: "became_apart", timestamp: null }]);
  assert.deepEqual(s, { totalDaysTogether: 0, totalDaysApart: 0 });
});

test("a stored calendar day reads back as the same day, in whatever zone this runs", () => {
  const picked = new Date(2026, 7, 19); // Aug 19, local
  const stored = storedFromLocalDay(picked);
  assert.equal(stored.toISOString(), "2026-08-19T12:00:00.000Z");
  assert.deepEqual(ymd(dayFromStored(stored)), [2026, 8, 19]);
});

test("a day stored by a partner in another zone keeps its day here", () => {
  // What a Tokyo partner's client writes for Aug 19.
  const fromTokyo = new Date(Date.UTC(2026, 7, 19, 12));
  assert.deepEqual(ymd(dayFromStored(fromTokyo)), [2026, 8, 19]);
});

test("yearly date later this year stays in this year", () => {
  const next = nextOccurrence(new Date(2020, 7, 19), true, new Date(2026, 2, 1));
  assert.deepEqual(ymd(next), [2026, 8, 19]);
});

test("yearly date already passed rolls to next year", () => {
  const next = nextOccurrence(new Date(2020, 7, 19), true, new Date(2026, 8, 1));
  assert.deepEqual(ymd(next), [2027, 8, 19]);
});

test("yearly date that is today stays today", () => {
  const now = new Date(2026, 8, 24, 15, 30);
  const next = nextOccurrence(new Date(2020, 8, 24), true, now);
  assert.equal(daysUntil(next, now), 0);
});

test("non-repeating date is returned as-is", () => {
  const d = new Date(2019, 5, 1);
  assert.equal(nextOccurrence(d, false, new Date()), d);
});

test("relative day labels", () => {
  assert.equal(relativeDayLabel(0), "Today");
  assert.equal(relativeDayLabel(1), "Tomorrow");
  assert.equal(relativeDayLabel(12), "in 12 days");
  assert.equal(relativeDayLabel(-1), "Yesterday");
  assert.equal(relativeDayLabel(-3), "3 days ago");
});

test("addDays moves by calendar days, even across a DST change", () => {
  // Late evening before a spring-forward weekend (US: Mar 8, 2026).
  const lateNight = new Date(2026, 2, 7, 23, 30);
  assert.deepEqual(ymd(addDays(lateNight, 7)), [2026, 3, 14]);
  assert.equal(localISODate(addDays(lateNight, 7)), "2026-03-14");
  assert.deepEqual(ymd(parseLocalISODate("2026-03-14")), [2026, 3, 14]);
});

test("default visit start is a week out at 6 PM", () => {
  const d = defaultVisitStart(new Date(2026, 8, 24, 9, 15));
  assert.deepEqual([...ymd(d), d.getHours(), d.getMinutes()], [2026, 10, 1, 18, 0]);
});

const now = new Date(2026, 8, 24, 12, 0);
const visit = (id, hours) => ({ id, start: new Date(now.getTime() + hours * 3_600_000) });

test("next upcoming visit skips past ones and picks the earliest", () => {
  const visits = [visit("past", -5), visit("later", 72), visit("soon", 10)];
  assert.equal(nextUpcoming(visits, now).id, "soon");
  assert.equal(nextUpcoming([visit("past", -1)], now), null);
});

test("resolved meetup picks the sooner of current and planned", () => {
  const visits = [visit("a", 48)];
  assert.equal(resolvedNextMeetup(null, visits, null, now), visits[0].start);
  assert.equal(resolvedNextMeetup(new Date(now - 60_000), visits, null, now), visits[0].start);
  const earlier = new Date(now.getTime() + 3_600_000);
  assert.equal(resolvedNextMeetup(earlier, visits, null, now), earlier);
});

test("removing the current visit moves on to the next, or none", () => {
  const a = visit("a", 24);
  const b = visit("b", 96);
  assert.equal(resolvedNextMeetup(a.start, [b], a, now), b.start);
  assert.equal(resolvedNextMeetup(a.start, [], a, now), null);
  assert.equal(resolvedNextMeetup(a.start, [a], b, now), a.start);
});

test("normalizedStart trims to the minute", () => {
  assert.equal(normalizedStart(new Date(1_800_000_123_456)).getTime(), 1_800_000_120_000);
});

test("month cells line the 1st up under its weekday", () => {
  const cells = monthCells(2026, 8); // September 2026 starts on a Tuesday
  assert.equal(cells.indexOf(null), 0);
  assert.equal(cells.filter((c) => c === null).length, 2);
  assert.deepEqual(ymd(cells[2]), [2026, 9, 1]);
  assert.equal(cells.length, 2 + 30);
});

test("countdownParts splits a duration and returns null once passed", () => {
  const start = new Date(2026, 0, 1);
  const target = new Date(start.getTime() + (2 * DAY + 3 * 3600_000 + 4 * 60_000 + 5_000));
  assert.deepEqual(countdownParts(target, start), { days: 2, hours: 3, minutes: 4, seconds: 5 });
  assert.equal(countdownParts(start, target), null);
});

test("unseen pings: the partner's recent, undismissed ones, newest first (same case as the Swift test)", () => {
  const now = new Date(1_800_000_000_000);
  const ping = (id, sentBy, hoursAgo, seen = false) => ({ id, sentBy, sentAt: new Date(now - hoursAgo * 3_600_000), seenAt: seen ? now : null });
  const pings = [
    ping("mine", "me", 1),
    ping("older", "partner", 30),
    ping("newest", "partner", 2),
    ping("dismissed", "partner", 3, true),
    ping("stale", "partner", 24 * 6),
  ];
  assert.deepEqual(unseenPings(pings, "me", now).map((p) => p.id), ["newest", "older"]);
  assert.deepEqual(unseenPings(pings, "partner", now).map((p) => p.id), ["mine"]);
});

test("ping headline", () => {
  assert.equal(pingHeadline("Sam", 1), "Sam is thinking of you");
  assert.equal(pingHeadline("Sam", 3), "Sam thought of you 3 times");
  assert.equal(pingHeadline(undefined, 1), "Your partner is thinking of you");
});

test("timeAgo", () => {
  const now = new Date(1_800_000_000_000);
  const ago = (ms) => timeAgo(new Date(now - ms), now, "en");
  assert.equal(ago(20_000), "just now");
  assert.equal(ago(5 * 60_000), "5 minutes ago");
  assert.equal(ago(2 * 3_600_000), "2 hours ago");
  assert.equal(ago(26 * 3_600_000), "yesterday");
  assert.equal(ago(3 * 86_400_000), "3 days ago");
});

// ---------- time apart (same cases as SeparationTests in the Swift suite) ----------
const t0 = new Date(1_800_000_000_000);
const dayN = (n) => new Date(t0.getTime() + n * DAY);
const ev = (type, at) => ({ type, timestamp: at });

test("pairing starts the first stretch apart", () => {
  const events = [ev("became_together", dayN(44))];
  const stats = computeStats(events, dayN(50), t0);
  assert.ok(Math.abs(stats.totalDaysApart - 44) < 1e-6);
  assert.ok(Math.abs(stats.totalDaysTogether - 6) < 1e-6);
  assert.equal(computeStats(events, dayN(50)).totalDaysApart, 0); // older pairings: as before
  assert.deepEqual(separations([], t0), [{ start: t0, end: null }]);
});

test("separations run from parting to reunion and ignore repeats", () => {
  const events = [
    ev("became_together", dayN(44)), ev("became_together", dayN(44.001)),
    ev("became_apart", dayN(50)), ev("became_apart", dayN(50.001)),
    ev("became_together", dayN(80)), ev("became_apart", dayN(85)),
  ];
  assert.deepEqual(separations(events, t0), [
    { start: t0, end: dayN(44) },
    { start: dayN(50), end: dayN(80) },
    { start: dayN(85), end: null },
  ]);
});

test("duration labels, stat days, and reunion messages", () => {
  assert.equal(durationLabel(20_000), "less than a minute");
  assert.equal(durationLabel(60_000), "1 minute");
  assert.equal(durationLabel(5 * 3_600_000), "5 hours");
  assert.equal(durationLabel(DAY + 5 * 3_600_000), "1 day, 5 hours");
  assert.equal(durationLabel(2 * DAY), "2 days");
  assert.equal(durationLabel(44.5 * DAY), "44 days");
  assert.equal(formatStatDays(0.83), "0.8");
  assert.equal(formatStatDays(23.6), "24");
  assert.equal(reunionMessage(null, 44 * DAY), "Congratulations! You're together again after 44 days apart 💞");
  assert.equal(reunionMessage(null, 30_000), "Congratulations! You're together again 💞");
  assert.equal(reunionMessage("Sam", 2 * DAY), "Sam says you're together after 2 days apart! Congratulations 💞");
  assert.equal(reunionMessage("Sam", null), "Sam says you're together! Congratulations 💞");
});

test("meeting early finds the visit that was counted down to", () => {
  const nowT = new Date(1_800_000_000_000);
  const planned = { id: "v", start: new Date(nowT.getTime() + DAY) };
  const later = { id: "w", start: new Date(nowT.getTime() + 30 * DAY) };
  assert.equal(visitMetEarly(planned.start, [later, planned], nowT)?.id, "v");
  assert.equal(visitMetEarly(new Date(nowT.getTime() - 60_000), [planned], nowT), null);
  // A week out is a separate trip: seeing each other now doesn't cancel it.
  const nextWeek = { id: "n", start: new Date(nowT.getTime() + 7 * DAY) };
  assert.equal(visitMetEarly(nextWeek.start, [nextWeek], nowT), null);
  assert.equal(visitMetEarly(null, [planned], nowT), null);
});

test("a time entered in another zone is that zone's wall clock, wherever this runs", () => {
  assert.equal(zonedTime(2026, 10, 1, 18, 30, "America/Chicago").toISOString(), "2026-10-01T23:30:00.000Z");
  assert.equal(zonedTime(2026, 10, 1, 18, 30, "Asia/Tokyo").toISOString(), "2026-10-01T09:30:00.000Z");
  // Just after a spring-forward (US: Mar 8, 2026, 2 AM → 3 AM): 3:30 AM is EDT.
  assert.equal(zonedTime(2026, 3, 8, 3, 30, "America/New_York").toISOString(), "2026-03-08T07:30:00.000Z");
  // Auckland in summer (UTC+13).
  assert.equal(zonedTime(2026, 1, 15, 9, 0, "Pacific/Auckland").toISOString(), "2026-01-14T20:00:00.000Z");
});
