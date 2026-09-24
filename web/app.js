// app.js — CoupleCountdown web client. Same Firebase project, data model, and
// Security Rules as the iPhone app, so a partner on the web and a partner on an
// iPhone share one countdown. Feature set: pairing, live countdown, apart/together
// toggle, important dates, stats, thinking-of-you, themes.

import { initializeApp } from "firebase/app";
import { getAuth, onAuthStateChanged, signInAnonymously, signOut } from "firebase/auth";
import { getFirestore, onSnapshot } from "firebase/firestore";
import { firebaseConfig } from "./firebase-config.js";
import { makeApi, generateJoinCode, normalizeCode } from "./data.js";
import {
  computeStats,
  countdownParts,
  daysUntil,
  localTimeLabel,
  nextOccurrence,
} from "./logic.js";

const fbApp = initializeApp(firebaseConfig);
const auth = getAuth(fbApp);
const db = getFirestore(fbApp);

const $app = document.getElementById("app");
const timeZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";

// localStorage can throw (private mode, blocked storage) — the app must still run.
const store = {
  get: (k) => { try { return localStorage.getItem(k); } catch { return null; } },
  set: (k, v) => { try { localStorage.setItem(k, v); } catch { /* per-session only */ } },
  del: (k) => { try { localStorage.removeItem(k); } catch { /* nothing to do */ } },
};

const THEMES = [
  { id: "blush", name: "Blush", emoji: "💗", color: "#ff6f91" },
  { id: "sunset", name: "Sunset", emoji: "🌅", color: "#ff7b54" },
  { id: "midnight", name: "Midnight", emoji: "🌙", color: "#c77dff" },
];

const S = {
  uid: null,
  api: null,
  name: store.get("displayName") || "",
  coupleId: store.get("coupleId") || "",
  prefillCode: normalizeCode(new URLSearchParams(location.search).get("join") || ""),
  step: "name", // onboarding: name | choice | create | join
  tab: "home",
  couple: null,
  loadError: null,
  unsub: null,
  busy: false,
  newCode: null,
  creating: false,
  createError: null,
};

// ---------- tiny DOM helper ----------
function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k === "class") el.className = v;
    else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else if (v === true) el.setAttribute(k, "");
    else el.setAttribute(k, v);
  }
  for (const kid of kids.flat()) {
    if (kid == null || kid === false) continue;
    el.append(kid.nodeType ? kid : document.createTextNode(kid));
  }
  return el;
}

function mount(...nodes) {
  $app.replaceChildren(...nodes);
}

function friendly(e, fallback) {
  const code = e?.code || "";
  if (code.includes("permission-denied") || code.includes("not-found")) return fallback;
  if (code.includes("unavailable") || code.includes("network")) return "Can't reach the server — check your connection and try again.";
  return fallback || e?.message || "Something went wrong.";
}

/** Local-calendar YYYY-MM-DD, `n` days from today (toISOString would use UTC and can be a day off). */
function isoDate(n = 0) {
  const d = new Date(Date.now() + n * 86_400_000);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

function applyTheme(id) {
  const theme = THEMES.find((t) => t.id === id) || THEMES[0];
  document.documentElement.dataset.theme = theme.id;
  document.querySelector('meta[name="theme-color"]')?.setAttribute("content", theme.color);
  store.set("theme", theme.id);
}

// ---------- boot ----------
function ensureUser() {
  return new Promise((resolve, reject) => {
    const off = onAuthStateChanged(
      auth,
      async (user) => {
        off();
        if (user) return resolve(user);
        try {
          resolve((await signInAnonymously(auth)).user);
        } catch (e) {
          reject(e);
        }
      },
      reject,
    );
  });
}

async function boot() {
  applyTheme(store.get("theme") || "blush");
  try {
    const user = await ensureUser();
    S.uid = user.uid;
    S.api = makeApi(db, user.uid);
  } catch (e) {
    console.error("Sign-in failed", e);
    mount(
      h("div", { class: "center" }, h("div", { class: "stack" },
        h("h2", {}, "Couldn't sign in"),
        h("p", { class: "muted" }, friendly(e, "Check your connection and try again.")),
        h("button", { class: "btn primary", onclick: () => location.reload() }, "Try again"),
      )),
    );
    return;
  }
  if (S.coupleId) enterMain();
  else {
    S.step = S.name ? (S.prefillCode ? "join" : "choice") : "name";
    renderOnboarding();
  }
}

// ---------- onboarding ----------
function renderOnboarding() {
  const views = { name: nameView, choice: choiceView, create: createView, join: joinView };
  mount(h("div", { class: "stack" }, headerTop(), views[S.step]()));
}

function headerTop() {
  return h("header", { class: "top" }, h("h1", {}, "💕 CoupleCountdown"));
}

function nameView() {
  const input = h("input", { type: "text", id: "nameInput", placeholder: "Your name", autocomplete: "given-name", maxlength: "30", value: S.name });
  const go = h("button", { class: "btn primary", id: "continueButton", disabled: !S.name.trim(), onclick: () => {
    S.name = input.value.trim();
    store.set("displayName", S.name);
    S.step = S.prefillCode ? "join" : "choice";
    renderOnboarding();
  } }, "Continue");
  input.addEventListener("input", () => { go.disabled = !input.value.trim(); });
  input.addEventListener("keydown", (e) => { if (e.key === "Enter" && !go.disabled) go.click(); });
  return h("div", { class: "card stack" },
    h("h2", {}, "What should your partner see your name as?"),
    input, go);
}

function choiceView() {
  return h("div", { class: "card stack" },
    h("h2", {}, "Let's get you two set up"),
    h("p", { class: "muted" }, "Only one of you should tap Create — have your partner tap Join with the code you'll get next."),
    h("button", { class: "btn primary", id: "createPairingButton", onclick: () => { S.step = "create"; S.newCode = null; startCreate(); } }, "✨ Create a pairing"),
    h("button", { class: "btn", id: "joinPairingButton", onclick: () => { S.step = "join"; renderOnboarding(); } }, "💌 Join a pairing"),
  );
}

async function startCreate() {
  if (S.creating) return;
  S.creating = true;
  S.createError = null;
  if (S.step === "create") renderOnboarding();
  const code = generateJoinCode();
  try {
    await S.api.createCouple(code, S.name, timeZone());
    S.newCode = code;
  } catch (e) {
    console.error("createCouple failed", e);
    S.createError = friendly(e, "Couldn't create the pairing — try again.");
  }
  S.creating = false;
  if (S.step === "create") renderOnboarding();
}

function createView() {
  if (S.creating) return h("div", { class: "card center" }, h("p", { class: "muted" }, "Creating…"));
  if (S.createError) {
    return h("div", { class: "card stack" },
      h("p", { class: "error" }, S.createError),
      h("button", { class: "btn primary", onclick: () => startCreate() }, "Try again"));
  }
  if (!S.newCode) return h("div", { class: "card center" }, h("p", { class: "muted" }, "Creating…"));
  // coupleId is only committed when the user taps Continue — advancing on
  // write success (as the iPhone app once did) hid the code before it could
  // be read or shared.
  return h("div", { class: "card stack" },
    h("h2", {}, "Your code"),
    h("div", { class: "code", id: "generatedCode" }, S.newCode),
    shareButtons(S.newCode),
    h("p", { class: "muted small" }, "Send this to your partner. They tap “Join a pairing” and enter it — on the web or in the iPhone app."),
    h("button", { class: "btn primary", id: "continueToCountdownButton", onclick: () => {
      S.coupleId = S.newCode;
      store.set("coupleId", S.coupleId);
      enterMain();
    } }, "Continue"),
  );
}

function shareButtons(code) {
  const link = `${location.origin}/?join=${code}`;
  const status = h("span", { class: "muted small" });
  const share = h("button", { class: "btn", id: "shareButton", onclick: async () => {
    try {
      if (navigator.share) await navigator.share({ title: "CoupleCountdown", text: `Join me on CoupleCountdown with code ${code}`, url: link });
      else {
        await navigator.clipboard.writeText(link);
        status.textContent = "Link copied";
      }
    } catch { /* share sheet dismissed */ }
  } }, navigator.share ? "Share invite" : "Copy invite link");
  return h("div", { class: "stack" }, share, status);
}

function joinView() {
  const input = h("input", { type: "text", id: "joinCodeInput", placeholder: "ABC123", autocapitalize: "characters", autocomplete: "off", spellcheck: "false", maxlength: "12", value: S.prefillCode });
  const error = h("p", { class: "error", id: "joinError", hidden: true });
  const go = h("button", { class: "btn primary", id: "joinButton", disabled: !S.prefillCode, onclick: async () => {
    const code = normalizeCode(input.value);
    if (!code) return;
    go.disabled = true;
    error.hidden = true;
    try {
      await S.api.joinCouple(code, S.name, timeZone());
      S.coupleId = code;
      store.set("coupleId", code);
      enterMain();
    } catch (e) {
      console.error("joinCouple failed", e);
      // Deliberately generic: a wrong, already-full, or expired code all fail
      // the Security Rules identically (permission denied).
      error.textContent = friendly(e, "Couldn't join — check the code and try again.");
      error.hidden = false;
      go.disabled = false;
    }
  } }, "Join");
  input.addEventListener("input", () => { go.disabled = !input.value.trim(); });
  input.addEventListener("keydown", (e) => { if (e.key === "Enter" && !go.disabled) go.click(); });
  return h("div", { class: "card stack" },
    h("h2", {}, "Enter your partner's code"),
    input, error, go,
    h("button", { class: "btn link", onclick: () => { S.prefillCode = ""; S.step = "choice"; renderOnboarding(); } }, "Back"),
  );
}

// ---------- main shell ----------
const TABS = [
  ["home", "Countdown"],
  ["dates", "Dates"],
  ["stats", "Stats"],
  ["theme", "Theme"],
];

function enterMain() {
  S.tab = "home";
  S.couple = null;
  S.loadError = null;
  renderShell();
  listen();
}

function listen() {
  S.unsub?.();
  S.unsub = onSnapshot(
    S.api.coupleRef(S.coupleId),
    (snap) => {
      if (!snap.exists()) {
        S.loadError = "We couldn't find this pairing anymore.";
      } else {
        const d = snap.data();
        S.couple = {
          status: d.status,
          nextMeetupDate: d.nextMeetupDate?.toDate?.() ?? null,
          participantUIDs: d.participantUIDs || [],
          partnerProfiles: d.partnerProfiles || {},
        };
        S.loadError = null;
      }
      if (S.tab === "home") renderTab();
    },
    (err) => {
      console.error("Listener failed", err);
      S.loadError = "Can't open this pairing on this device. It may have been created by a different browser — start over to pair again.";
      if (S.tab === "home") renderTab();
    },
  );
}

function renderShell() {
  const nav = h("nav", { class: "tabs" }, TABS.map(([id, label]) =>
    h("button", { "data-tab": id, "aria-current": S.tab === id ? "page" : null, onclick: () => { S.tab = id; renderShell(); } }, label)));
  mount(h("div", {}, headerTop(), nav, h("div", { id: "content" })));
  renderTab();
}

function renderTab() {
  const content = document.getElementById("content");
  if (!content) return;
  const views = { home: homeView, dates: datesView, stats: statsView, theme: themeView };
  content.replaceChildren(views[S.tab]());
  updateUnits();
}

// ---------- home ----------
function homeView() {
  if (S.loadError) {
    return h("div", { class: "card stack" }, h("p", { class: "error" }, S.loadError), startOverButton());
  }
  const c = S.couple;
  if (!c) return h("div", { class: "card center" }, h("p", { class: "muted" }, "Loading…"));

  const together = c.status === "together";
  const parts = [];

  if (c.participantUIDs.length < 2) {
    parts.push(h("div", { class: "card stack", id: "waitingCard" },
      h("h2", {}, "Waiting for your partner 💌"),
      h("div", { class: "code" }, S.coupleId),
      shareButtons(S.coupleId)));
  }

  parts.push(countdownCard(c));
  parts.push(h("div", { class: "row spread", style: "margin-bottom:16px" },
    h("span", { class: "badge", id: "statusBadge" }, together ? "❤️ Together right now" : "🤍 Apart, for now")));

  const clocks = Object.values(c.partnerProfiles).map((p) => localTimeLabel(p.displayName, p.timeZoneIdentifier));
  if (clocks.length) parts.push(h("p", { class: "muted small", id: "clocks" }, clocks.join("  ·  ")));

  const error = h("p", { class: "error", id: "homeError", hidden: true });
  const toggle = h("button", { class: "btn primary", id: "toggleStatusButton", onclick: () => onToggle(toggle, error) },
    together ? "✈️ Leaving again" : "❤️ We're together now");
  const ping = h("button", { class: "btn", id: "thinkingOfYouButton", onclick: () => onPing(ping, error) }, "💌 Send a little “thinking of you”");
  parts.push(h("div", { class: "stack" }, toggle, ping, error));
  return h("div", {}, parts);
}

function countdownCard(c) {
  if (c.status === "together") {
    return h("div", { class: "card countdown" }, h("div", { class: "empty-big" }, "💞"), h("h2", {}, "You're together"), h("p", { class: "muted" }, "Enjoy every minute."));
  }
  if (!c.nextMeetupDate) {
    return h("div", { class: "card countdown" }, h("div", { class: "empty-big" }, "🗓️"), h("h2", { id: "noDateText" }, "No date set yet"), h("p", { class: "muted" }, "When do you see each other next?"), setDateButton("Set the date"));
  }
  if (c.nextMeetupDate <= new Date()) {
    return h("div", { class: "card countdown" }, h("div", { class: "empty-big" }, "🎉"), h("h2", {}, "The day is here"), h("p", { class: "muted" }, "Tap “We're together now” when you meet — or pick a new date if plans changed."), setDateButton("Pick a new date"));
  }
  return h("div", { class: "card countdown" },
    h("div", { class: "label" }, "Until we're together again"),
    h("div", { class: "units", id: "units" },
      ["days", "hours", "minutes", "seconds"].map((u) => h("div", { class: "unit" }, h("b", { id: `u-${u}` }, "–"), h("span", {}, u)))));
}

function setDateButton(label) {
  return h("button", { class: "btn", id: "setDateButton", style: "margin-top:12px", onclick: () => openDateModal() }, label);
}

function updateUnits() {
  const c = S.couple;
  if (!c || c.status !== "apart" || !c.nextMeetupDate || !document.getElementById("units")) return;
  const p = countdownParts(c.nextMeetupDate);
  if (!p) { if (S.tab === "home") renderTab(); return; }
  for (const u of ["days", "hours", "minutes", "seconds"]) {
    const el = document.getElementById(`u-${u}`);
    if (el) el.textContent = String(p[u]).padStart(u === "days" ? 1 : 2, "0");
  }
}
setInterval(updateUnits, 1000);

async function onToggle(button, error) {
  const c = S.couple;
  if (!c || S.busy) return;
  const next = c.status === "apart" ? "together" : "apart";
  // Every departure is a new trip, so always ask for the next date. (The
  // iPhone app only asks when no date exists, so a second goodbye there
  // shows the previous trip's expired countdown.)
  if (next === "apart") {
    openDateModal();
    return;
  }
  S.busy = true;
  button.disabled = true;
  error.hidden = true;
  try {
    await S.api.setStatus(S.coupleId, next);
  } catch (e) {
    console.error("setStatus failed", e);
    error.textContent = "Couldn't update — check your connection and try again.";
    error.hidden = false;
  }
  S.busy = false;
  button.disabled = false;
}

async function onPing(button, error) {
  if (button.disabled) return;
  button.disabled = true;
  error.hidden = true;
  const label = button.textContent;
  try {
    await S.api.sendPing(S.coupleId);
    button.textContent = "💗 Sent, with love";
    setTimeout(() => { button.textContent = label; button.disabled = false; }, 2000);
  } catch (e) {
    console.error("sendPing failed", e);
    error.textContent = "Couldn't send — try again.";
    error.hidden = false;
    button.disabled = false;
  }
}

function openDateModal() {
  const input = h("input", { type: "date", id: "nextMeetupDateInput", value: isoDate(7), min: isoDate(0) });
  const error = h("p", { class: "error", hidden: true });
  const close = () => backdrop.remove();
  const save = h("button", { class: "btn primary", id: "saveDateButton", onclick: async () => {
    if (!input.value) return;
    const [y, m, d] = input.value.split("-").map(Number);
    save.disabled = true;
    try {
      await S.api.setStatus(S.coupleId, "apart", new Date(y, m - 1, d));
      close();
    } catch (e) {
      console.error("setStatus (date) failed", e);
      error.textContent = "Couldn't save the date — check your connection and try again.";
      error.hidden = false;
      save.disabled = false;
    }
  } }, "Save");
  const backdrop = h("div", { class: "modal-backdrop", onclick: (e) => { if (e.target === backdrop) close(); } },
    h("div", { class: "modal stack", role: "dialog", "aria-modal": "true", "aria-label": "When do you see each other next?" },
      h("h2", {}, "When do you leave? ✈️"),
      h("label", { class: "field" }, "Next meetup", input),
      error, save,
      h("button", { class: "btn link", onclick: close }, "Cancel")));
  document.body.append(backdrop);
  input.focus();
}

// ---------- dates ----------
function datesView() {
  const list = h("div", { id: "datesList" }, h("p", { class: "muted" }, "Loading…"));
  const label = h("input", { type: "text", id: "dateLabelInput", placeholder: "Label (e.g. Anniversary)", maxlength: "60" });
  const date = h("input", { type: "date", id: "importantDateInput", value: isoDate(0) });
  const repeats = h("input", { type: "checkbox", id: "repeatsAnnuallyInput", checked: true });
  const error = h("p", { class: "error", hidden: true });
  const save = h("button", { class: "btn primary", id: "saveImportantDateButton", disabled: true, onclick: async () => {
    if (!label.value.trim() || !date.value) return;
    const [y, m, d] = date.value.split("-").map(Number);
    save.disabled = true;
    error.hidden = true;
    try {
      await S.api.addImportantDate(S.coupleId, { label: label.value.trim(), date: new Date(y, m - 1, d), repeatsAnnually: repeats.checked });
      label.value = "";
      await loadDates(list);
    } catch (e) {
      console.error("addImportantDate failed", e);
      error.textContent = "Couldn't save — check your connection and try again.";
      error.hidden = false;
    }
    save.disabled = !label.value.trim();
  } }, "Add date");
  label.addEventListener("input", () => { save.disabled = !label.value.trim(); });
  loadDates(list);
  return h("div", {},
    h("div", { class: "card" }, h("h2", {}, "📅 Important dates"), list),
    h("div", { class: "card stack" },
      h("h2", {}, "Add one"),
      label,
      h("label", { class: "field" }, "Date", date),
      h("label", { class: "check" }, repeats, "Repeats every year"),
      error, save));
}

async function loadDates(list) {
  try {
    const dates = (await S.api.fetchImportantDates(S.coupleId))
      .map((d) => ({ ...d, next: nextOccurrence(d.date, d.repeatsAnnually) }))
      .sort((a, b) => a.next - b.next);
    if (!list.isConnected) return;
    if (!dates.length) {
      list.replaceChildren(h("p", { class: "muted", id: "noDatesText" }, "No important dates yet — add your anniversary or another date worth counting down to."));
      return;
    }
    list.replaceChildren(h("ul", { class: "list" }, dates.map((d) => {
      const n = daysUntil(d.next);
      const until = n === 0 ? "Today 🎉" : n > 0 ? `${n} day${n === 1 ? "" : "s"}` : `${-n} day${n === -1 ? "" : "s"} ago`;
      return h("li", { "data-label": d.label },
        h("div", {}, h("div", {}, `${d.repeatsAnnually ? "🎁" : "⭐"} ${d.label}`),
          h("div", { class: "when" }, d.next.toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" }))),
        h("span", { class: "until" }, until));
    })));
  } catch (e) {
    console.error("fetchImportantDates failed", e);
    if (list.isConnected) list.replaceChildren(h("p", { class: "error" }, "Couldn't load — switch tabs to try again."));
  }
}

// ---------- stats ----------
function statsView() {
  const body = h("div", { class: "stack" }, h("p", { class: "muted" }, "Loading…"));
  (async () => {
    try {
      const stats = computeStats(await S.api.fetchEvents(S.coupleId));
      const fmt = (n) => (n < 10 ? n.toFixed(1) : String(Math.round(n)));
      if (!body.isConnected) return;
      body.replaceChildren(
        h("div", { class: "stat", id: "daysTogetherStat" }, h("span", {}, "❤️ Days together"), h("b", {}, fmt(stats.totalDaysTogether))),
        h("div", { class: "stat", id: "daysApartStat" }, h("span", {}, "✈️ Days apart"), h("b", {}, fmt(stats.totalDaysApart))));
    } catch (e) {
      console.error("fetchEvents failed", e);
      if (body.isConnected) body.replaceChildren(h("p", { class: "error" }, "Couldn't load stats."));
    }
  })();
  return h("div", { class: "card" }, h("h2", {}, "💞 Stats"), body);
}

// ---------- theme / settings ----------
function themeView() {
  const current = store.get("theme") || "blush";
  const swatches = THEMES.map((t) => h("button", { class: "swatch", id: `theme_${t.id}`, "aria-pressed": String(t.id === current), onclick: () => { applyTheme(t.id); renderTab(); } },
    h("span", { class: "dot", style: `background:${t.color}` }), `${t.emoji} ${t.name}`, t.id === current ? h("span", { style: "margin-left:auto" }, "✓") : null));
  return h("div", {},
    h("div", { class: "card stack" }, h("h2", {}, "Theme"), h("p", { class: "muted small" }, "Saved on this device."), h("div", { class: "swatches" }, swatches)),
    h("div", { class: "card stack" }, h("h2", {}, "This device"),
      h("p", { class: "muted small" }, `Pairing code ${S.coupleId}. Each browser or phone has its own identity, and a pairing holds exactly two people — so this device can't be a third.`),
      startOverButton()));
}

function startOverButton() {
  return h("button", { class: "btn", id: "startOverButton", onclick: async () => {
    if (!confirm("Leave this pairing on this device? You'll need a new code to pair again.")) return;
    S.unsub?.();
    store.del("coupleId");
    try { await signOut(auth); } catch { /* reload signs in fresh regardless */ }
    location.href = location.pathname;
  } }, "Start over on this device");
}

boot();
