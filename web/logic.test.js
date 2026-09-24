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
  defaultVisitStart,
  localISODate,
  monthCells,
  nextOccurrence,
  nextUpcoming,
  normalizedStart,
  parseLocalISODate,
  relativeDayLabel,
  resolvedNextMeetup,
  storedFromLocalDay,
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
