// logic.js — pure functions ported from CoupleCountdownKit (CumulativeStatsCalculator,
// ImportantDate, CalendarDay, MeetupPlanner, CountdownFormatter). No DOM, no Firebase,
// so they run in the browser and under `node --test` unchanged. Keep in step with the
// Swift versions — both apps read the same data.

const DAY_MS = 86_400_000;
const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

/** `date` moved by `n` calendar days. Uses setDate, not n × 24h, so DST can't shift the day. */
export function addDays(date, n) {
  const d = new Date(date);
  d.setDate(d.getDate() + n);
  return d;
}

/** Local-calendar "YYYY-MM-DD" (toISOString would be UTC, and can be a day off). */
export function localISODate(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

/** "YYYY-MM-DD" (a date input's value) → local midnight of that day. */
export function parseLocalISODate(value) {
  const [y, m, d] = value.split("-").map(Number);
  return new Date(y, m - 1, d);
}

// ---------- calendar days (anniversaries, birthdays) ----------
// A day with no time of day must read as the same day for both partners.
// Stored as 12:00 UTC on that day and read back with UTC components — see
// CalendarDay.swift. Storing local midnight showed dates a day early to a
// partner further west.

/** A picked day (any Date on it, local) → the value to store. */
export function storedFromLocalDay(date) {
  return new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate(), 12));
}

/** A stored value → local midnight of the day it represents. */
export function dayFromStored(stored) {
  return new Date(stored.getUTCFullYear(), stored.getUTCMonth(), stored.getUTCDate());
}

/**
 * Next occurrence (local midnight) of a day given as local midnight. A yearly
 * date on today's day is today, not next year — compared against the start of
 * today, not the current instant.
 */
export function nextOccurrence(date, repeatsAnnually, now = new Date()) {
  if (!repeatsAnnually) return date;
  const candidate = new Date(now.getFullYear(), date.getMonth(), date.getDate());
  if (candidate >= startOfDay(now)) return candidate;
  return new Date(now.getFullYear() + 1, date.getMonth(), date.getDate());
}

/** Calendar days from today to `target` (0 = today, negative = past). */
export function daysUntil(target, now = new Date()) {
  return Math.round((startOfDay(target) - startOfDay(now)) / DAY_MS);
}

/** "Today", "Tomorrow", "in 12 days", "Yesterday", "3 days ago". */
export function relativeDayLabel(days) {
  if (days === 0) return "Today";
  if (days === 1) return "Tomorrow";
  if (days === -1) return "Yesterday";
  return days > 1 ? `in ${days} days` : `${-days} days ago`;
}

// ---------- visits (planned meetups) ----------
// How nextMeetupDate — what the main countdown and the widget count down
// to — follows the planned visits. Mirrors MeetupPlanner.swift.

/** The earliest visit that hasn't started yet. */
export function nextUpcoming(visits, now = new Date()) {
  return visits
    .filter((v) => v.start > now)
    .reduce((best, v) => (!best || v.start < best.start ? v : best), null);
}

/**
 * nextMeetupDate after the visits change. A still-upcoming `current` that no
 * visit accounts for (set before visits existed) is kept unless a planned
 * visit comes sooner; if `removed` was the one it pointed at, it moves on.
 */
export function resolvedNextMeetup(current, visits, removed = null, now = new Date()) {
  let cur = current;
  if (removed && cur && Math.abs(cur - removed.start) < 1000) cur = null;
  const upcoming = nextUpcoming(visits, now)?.start ?? null;
  if (!cur || cur <= now) return upcoming;
  if (!upcoming) return cur;
  return upcoming < cur ? upcoming : cur;
}

/** Trim a picked date-time to the minute, so it compares equal after a Firestore round trip. */
export function normalizedStart(date) {
  return new Date(Math.floor(date.getTime() / 60_000) * 60_000);
}

/** Default for a new visit: a week from today at 6 PM. */
export function defaultVisitStart(now = new Date()) {
  const d = addDays(startOfDay(now), 7);
  d.setHours(18, 0, 0, 0);
  return d;
}

// ---------- month grid ----------

/** Days of a month as local midnights, preceded by nulls to line the 1st up under its weekday (Sunday-first). */
export function monthCells(year, month) {
  const first = new Date(year, month, 1);
  const count = new Date(year, month + 1, 0).getDate();
  const cells = Array(first.getDay()).fill(null);
  for (let day = 1; day <= count; day++) cells.push(new Date(year, month, day));
  return cells;
}

// ---------- countdown & stats ----------

/** Whole days/hours/minutes/seconds until `target`, or null once it has passed. */
export function countdownParts(target, now = new Date()) {
  const ms = target - now;
  if (ms <= 0) return null;
  const s = Math.floor(ms / 1000);
  return {
    days: Math.floor(s / 86400),
    hours: Math.floor((s % 86400) / 3600),
    minutes: Math.floor((s % 3600) / 60),
    seconds: s % 60,
  };
}

/**
 * Same algorithm as CumulativeStatsCalculator.swift: each event owns the span
 * until the next event (the last one until `now`). Events without a timestamp
 * (a write still pending on the server) are skipped.
 */
export function computeStats(events, now = new Date()) {
  const sorted = events
    .filter((e) => e.timestamp instanceof Date)
    .sort((a, b) => a.timestamp - b.timestamp);
  let together = 0;
  let apart = 0;
  sorted.forEach((event, i) => {
    const end = i + 1 < sorted.length ? sorted[i + 1].timestamp : now;
    const duration = end - event.timestamp;
    if (duration <= 0) return;
    if (event.type === "became_together") together += duration;
    else if (event.type === "became_apart") apart += duration;
  });
  return { totalDaysTogether: together / DAY_MS, totalDaysApart: apart / DAY_MS };
}

/** "Sam: 9:14 PM CDT" — display-only partner clock (DESIGN.md §9.1). */
export function localTimeLabel(label, timeZone, now = new Date()) {
  try {
    const time = new Intl.DateTimeFormat(undefined, {
      hour: "numeric",
      minute: "2-digit",
      timeZoneName: "short",
      timeZone,
    }).format(now);
    return `${label}: ${time}`;
  } catch {
    return label;
  }
}
