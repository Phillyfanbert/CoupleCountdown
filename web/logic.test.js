// Mirrors CoupleCountdownKitTests.swift so the web port can't drift from the
// iPhone app's behavior. Run: node --test web/
import test from "node:test";
import assert from "node:assert/strict";
import { computeStats, countdownParts, daysUntil, nextOccurrence } from "./logic.js";

const DAY = 86_400_000;

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

test("yearly date later this year stays in this year", () => {
  const next = nextOccurrence(new Date(2020, 7, 19), true, new Date(2026, 2, 1));
  assert.deepEqual([next.getFullYear(), next.getMonth(), next.getDate()], [2026, 7, 19]);
});

test("yearly date already passed rolls to next year", () => {
  const next = nextOccurrence(new Date(2020, 7, 19), true, new Date(2026, 8, 1));
  assert.deepEqual([next.getFullYear(), next.getMonth(), next.getDate()], [2027, 7, 19]);
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

test("countdownParts splits a duration and returns null once passed", () => {
  const now = new Date(2026, 0, 1);
  const target = new Date(now.getTime() + (2 * DAY + 3 * 3600_000 + 4 * 60_000 + 5_000));
  assert.deepEqual(countdownParts(target, now), { days: 2, hours: 3, minutes: 4, seconds: 5 });
  assert.equal(countdownParts(now, target), null);
});
