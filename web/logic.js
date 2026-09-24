// logic.js — pure functions ported from CoupleCountdownKit (CumulativeStatsCalculator,
// ImportantDate.nextOccurrence, CountdownFormatter). No DOM, no Firebase, so they run
// in the browser and under `node --test` unchanged.

const DAY_MS = 86_400_000;
const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

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

/** ImportantDate.nextOccurrence — yearly dates roll forward instead of going negative. */
export function nextOccurrence(date, repeatsAnnually, now = new Date()) {
  if (!repeatsAnnually) return date;
  const candidate = new Date(now.getFullYear(), date.getMonth(), date.getDate());
  // Compare against the start of today, not `now`: an anniversary that is
  // today is still "today", not already 365 days away. (ImportantDate.swift
  // compares against `now` and rolls a same-day date forward a year.)
  if (candidate >= startOfDay(now)) return candidate;
  return new Date(now.getFullYear() + 1, date.getMonth(), date.getDate());
}

/** Calendar days from today to `target` (0 = today, negative = past). */
export function daysUntil(target, now = new Date()) {
  return Math.round((startOfDay(target) - startOfDay(now)) / DAY_MS);
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
