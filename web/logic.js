// logic.js: pure functions ported from CoupleCountdownKit (CumulativeStatsCalculator,
// ImportantDate, CalendarDay, MeetupPlanner, CountdownFormatter). No DOM, no Firebase,
// so they run in the browser and under `node --test` unchanged. Keep in step with the
// Swift versions, both apps read the same data.

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
// Stored as 12:00 UTC on that day and read back with UTC components, see
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
 * date on today's day is today, not next year, compared against the start of
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
// How nextMeetupDate (what the main countdown and the widget count down
// to) follows the planned visits. Mirrors MeetupPlanner.swift.

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

/**
 * How close a planned visit has to be for "we're together now" to mean it's
 * happening early. Further out it's a separate trip: seeing each other this
 * weekend doesn't cancel the one planned for next week.
 */
export const MET_EARLY_WINDOW_MS = 24 * 3_600_000;

/**
 * Saying you're together shortly *before* the planned visit's start: that
 * visit is happening now. Returns the visit the countdown pointed at if it's
 * due within MET_EARLY_WINDOW_MS, so it can be moved to now, otherwise
 * "Leaving again" before its original time counted down to it again.
 * Mirrors MeetupPlanner.visitMetEarly.
 */
export function visitMetEarly(current, visits, now = new Date()) {
  if (!current || current <= now || current - now > MET_EARLY_WINDOW_MS) return null;
  return visits.find((v) => Math.abs(v.start - current) < 1000) ?? null;
}

/** Wall-clock parts of `date` in an IANA time zone. */
function partsIn(date, timeZone) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit",
  }).formatToParts(date);
  const get = (type) => Number(parts.find((p) => p.type === type).value);
  return { year: get("year"), month: get("month"), day: get("day"), hour: get("hour") % 24, minute: get("minute") };
}

/**
 * The instant when the clock in `timeZone` reads year-month-day hour:minute
 * (month 1–12), for entering a visit in the partner's time. Two passes so
 * a daylight-saving change between the guess and the answer can't skew it.
 */
export function zonedTime(year, month, day, hour, minute, timeZone) {
  const wall = Date.UTC(year, month - 1, day, hour, minute);
  const offset = (t) => {
    const p = partsIn(new Date(t), timeZone);
    return Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute) - Math.floor(t / 60_000) * 60_000;
  };
  let t = wall - offset(wall);
  t = wall - offset(t);
  return new Date(t);
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

/** "Sam Lee", or just "Sam" without a last name. Mirrors PartnerProfile.fullName. */
export function fullName(first, last) {
  return [first, last].map((part) => (part || "").trim()).filter(Boolean).join(" ");
}

// ---------- "thinking of you" ----------
// Mirrors ThinkingOfYouPing.swift.

/** How long a ping stays worth showing to the partner. */
export const PING_LIFETIME_MS = 5 * DAY_MS;

/** The pings `uid` should see: sent by the partner, not dismissed, recent. Newest first. */
export function unseenPings(pings, uid, now = new Date()) {
  return pings
    .filter((p) => p.sentBy !== uid && !p.seenAt && now - p.sentAt < PING_LIFETIME_MS)
    .sort((a, b) => b.sentAt - a.sentAt);
}

/** "Sam is thinking of you" / "Sam thought of you 3 times". */
export function pingHeadline(senderName, count) {
  const name = senderName || "Your partner";
  return count > 1 ? `${name} thought of you ${count} times` : `${name} is thinking of you`;
}

/** "just now", "5 minutes ago", "yesterday", "3 days ago" (in `locale`, default the browser's). */
export function timeAgo(date, now = new Date(), locale = undefined) {
  const seconds = Math.round((date - now) / 1000);
  if (seconds > -60) return "just now";
  const rtf = new Intl.RelativeTimeFormat(locale, { numeric: "auto" });
  const minutes = Math.round(seconds / 60);
  if (minutes > -60) return rtf.format(minutes, "minute");
  const hours = Math.round(minutes / 60);
  if (hours > -24) return rtf.format(hours, "hour");
  return rtf.format(Math.round(hours / 24), "day");
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
 * Events oldest first, preceded by the implicit "apart" at pairing: pairings
 * start apart, but no event marks it. Events without a timestamp (a write
 * still pending on the server) are skipped.
 */
function timeline(events, pairedAt) {
  const sorted = events
    .filter((e) => e.timestamp instanceof Date)
    .sort((a, b) => a.timestamp - b.timestamp);
  if (pairedAt && (!sorted.length || pairedAt < sorted[0].timestamp)) {
    sorted.unshift({ type: "became_apart", timestamp: pairedAt });
  }
  return sorted;
}

/**
 * Same algorithm as CumulativeStatsCalculator.swift: each event owns the span
 * until the next event (the last one until `now`). `pairedAt` starts the
 * first span, so the first separation counts.
 */
export function computeStats(events, now = new Date(), pairedAt = null) {
  const sorted = timeline(events, pairedAt);
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

/**
 * Every stretch apart, oldest first: { start, end } from each parting (or the
 * pairing) to the reunion that ended it; end is null while still apart.
 * Repeats of the same event don't start a new one. Mirrors
 * CumulativeStatsCalculator.separations.
 */
export function separations(events, pairedAt = null) {
  const result = [];
  let openSince = null;
  for (const event of timeline(events, pairedAt)) {
    if (event.type === "became_apart") {
      if (!openSince) openSince = event.timestamp;
    } else if (event.type === "became_together" && openSince) {
      result.push({ start: openSince, end: event.timestamp });
      openSince = null;
    }
  }
  if (openSince) result.push({ start: openSince, end: null });
  return result;
}

/** "3 days", "1 day, 5 hours", "5 hours", "12 minutes", "less than a minute". Mirrors CountdownFormatter.durationLabel. */
export function durationLabel(ms) {
  const minutes = Math.floor(Math.max(0, ms) / 60_000);
  const days = Math.floor(minutes / 1440), hours = Math.floor((minutes % 1440) / 60), mins = minutes % 60;
  const count = (n, unit) => `${n} ${unit}${n === 1 ? "" : "s"}`;
  if (days >= 3) return count(days, "day");
  if (days >= 1) return hours > 0 ? `${count(days, "day")}, ${count(hours, "hour")}` : count(days, "day");
  if (hours >= 1) return count(hours, "hour");
  if (mins >= 1) return count(mins, "minute");
  return "less than a minute";
}

/** A stats figure in days, same on both clients: "0.8" under 10, "23" from there. */
export function formatStatDays(days) {
  return days < 10 ? days.toFixed(1) : String(Math.round(days));
}

/** The reunion congratulations, with how long you were apart when it's an hour or more. Mirrors CountdownFormatter.reunionMessage. */
export function reunionMessage(partnerName, apartForMs) {
  const after = apartForMs != null && apartForMs >= 3_600_000 ? ` after ${durationLabel(apartForMs)} apart` : "";
  if (partnerName) return `${partnerName} says you're together${after}! Congratulations 💞`;
  return `Congratulations! You're together again${after} 💞`;
}

/** "Sam: 9:14 PM CDT": display-only partner clock (DESIGN.md §9.1). */
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
