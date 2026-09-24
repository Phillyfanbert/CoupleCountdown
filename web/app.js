// app.js — CoupleCountdown web client. Same Firebase project, data model, and
// Security Rules as the iPhone app, so a partner on the web and a partner on an
// iPhone share one countdown. Identity is an email + password account, so one
// person can be signed in on their phone and their computer at the same time;
// the pairing lives on the account (users/{uid}), not on any one device.

import { initializeApp } from "firebase/app";
import {
  createUserWithEmailAndPassword,
  EmailAuthProvider,
  getAuth,
  linkWithCredential,
  onAuthStateChanged,
  sendPasswordResetEmail,
  signInWithEmailAndPassword,
  signOut,
} from "firebase/auth";
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
// Only device preferences live here now (theme); identity and pairing are on the account.
const store = {
  get: (k) => { try { return localStorage.getItem(k); } catch { return null; } },
  set: (k, v) => { try { localStorage.setItem(k, v); } catch { /* per-session only */ } },
  del: (k) => { try { localStorage.removeItem(k); } catch { /* nothing to do */ } },
};

// Before accounts existed, this browser kept an anonymous identity plus its
// pairing and name here. Creating an account upgrades that identity in place
// (same uid), so an existing pairing carries over instead of being lost.
const legacy = { coupleId: store.get("coupleId"), name: store.get("displayName") };

const THEMES = [
  { id: "blush", name: "Blush", emoji: "💗", color: "#ff6f91" },
  { id: "sunset", name: "Sunset", emoji: "🌅", color: "#ff7b54" },
  { id: "midnight", name: "Midnight", emoji: "🌙", color: "#c77dff" },
];

const S = {
  user: null, // signed-in account (never an anonymous user)
  api: null,
  profile: null, // users/{uid} once loaded
  name: "",
  coupleId: "",
  prefillCode: normalizeCode(new URLSearchParams(location.search).get("join") || ""),
  authMode: "signup", // signup | signin
  authBusy: false, // suppresses the auth listener while a sign-in/up finishes its own writes
  screen: "loading", // loading | auth | onboarding | main
  step: "choice", // onboarding: name | choice | create | join
  tab: "home",
  couple: null,
  loadError: null,
  unsubProfile: null,
  unsubCouple: null,
  busy: false,
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

function authMessage(e) {
  const code = e?.code || "";
  if (/invalid-credential|wrong-password|user-not-found|invalid-login-credentials/.test(code)) return "Email or password is incorrect.";
  if (/email-already-in-use|credential-already-in-use/.test(code)) return "There's already an account with that email — sign in instead.";
  if (code.includes("invalid-email")) return "That doesn't look like an email address.";
  if (code.includes("weak-password") || code.includes("missing-password")) return "Use at least 6 characters for your password.";
  if (code.includes("too-many-requests")) return "Too many attempts — wait a minute and try again.";
  if (code.includes("network")) return "Can't reach the server — check your connection and try again.";
  return "Couldn't sign in — try again.";
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

function headerTop() {
  return h("header", { class: "top" }, h("h1", {}, "💕 CoupleCountdown"));
}

function loadingScreen(text) {
  S.screen = "loading";
  mount(headerTop(), h("div", { class: "center" }, h("p", { class: "muted" }, text)));
}

// ---------- session ----------
function boot() {
  applyTheme(store.get("theme") || "blush");
  loadingScreen("Loading…");
  onAuthStateChanged(auth, (user) => {
    if (!S.authBusy) startSession(user);
  });
}

function endSession() {
  S.unsubProfile?.();
  S.unsubCouple?.();
  Object.assign(S, { unsubProfile: null, unsubCouple: null, user: null, api: null, profile: null, name: "", coupleId: "", couple: null, loadError: null });
}

function startSession(user) {
  if (user && !user.isAnonymous && S.user?.uid === user.uid) return; // already running
  endSession();
  if (!user || user.isAnonymous) {
    renderAuth();
    return;
  }
  S.user = user;
  S.api = makeApi(db, user.uid);
  S.step = S.prefillCode ? "join" : "choice";
  loadingScreen("Loading your account…");
  // includeMetadataChanges so onProfile also hears when a local write is
  // confirmed by the server (see the pending-writes check in onProfile).
  S.unsubProfile = onSnapshot(S.api.userRef(), { includeMetadataChanges: true }, onProfile, (e) => {
    console.error("Profile listener failed", e);
    mount(headerTop(), h("div", { class: "card stack" },
      h("h2", {}, "Couldn't load your account"),
      h("p", { class: "muted" }, friendly(e, "Try again in a moment.")),
      h("button", { class: "btn primary", onclick: () => location.reload() }, "Try again"),
      signOutButton()));
  });
}

/**
 * Every device signed in to the same account watches users/{uid}, so pairing
 * (or cancelling) on one device moves all the others along with it.
 */
function onProfile(snap) {
  // Act only on server-confirmed state. Firestore reports this device's own
  // writes immediately, before the server has them — after "Create", that
  // meant opening the new pairing before the server had stored it; the rules
  // deny reading a pairing that doesn't exist yet, and a denied listener
  // never recovers, so the screen was stuck on "can't open that pairing".
  if (snap.metadata.hasPendingWrites) return;
  // Offline with nothing cached: we don't know the account's state yet.
  if (snap.metadata.fromCache && !snap.exists()) return;
  const p = snap.data() || {};
  S.profile = p;
  S.name = p.displayName || "";
  if (p.coupleId) {
    if (p.coupleId !== S.coupleId || S.screen !== "main") {
      S.coupleId = p.coupleId;
      enterMain();
    }
    return;
  }
  S.coupleId = "";
  S.unsubCouple?.();
  S.unsubCouple = null;
  S.couple = null;
  let step = S.step;
  if (!S.name) step = "name";
  else if (step === "name" || S.screen === "main") step = S.prefillCode ? "join" : "choice";
  if (step !== S.step || S.screen !== "onboarding") {
    S.step = step;
    renderOnboarding();
  }
}

// ---------- sign in / create account ----------
function renderAuth() {
  S.screen = "auth";
  const signup = S.authMode === "signup";
  const upgrading = auth.currentUser?.isAnonymous && legacy.coupleId;

  const name = signup ? h("input", { type: "text", id: "authNameInput", placeholder: "Your name (what your partner sees)", autocomplete: "given-name", maxlength: "30", value: legacy.name || "" }) : null;
  const email = h("input", { type: "email", id: "authEmailInput", placeholder: "Email", autocomplete: "email", autocapitalize: "off", spellcheck: "false" });
  const password = h("input", { type: "password", id: "authPasswordInput", placeholder: signup ? "Password (6+ characters)" : "Password", autocomplete: signup ? "new-password" : "current-password" });
  const error = h("p", { class: "error", id: "authError", hidden: true });
  const note = h("p", { class: "muted small", id: "authNote", hidden: true });

  const submit = h("button", { class: "btn primary", id: "authSubmitButton", type: "submit" }, signup ? "Create account" : "Sign in");
  const form = h("form", { class: "stack", onsubmit: (e) => {
    e.preventDefault();
    submitAuth({ name: name?.value.trim(), email: email.value.trim(), password: password.value }, error, submit);
  } }, name, email, password, error, submit);

  const forgot = signup ? null : h("button", { class: "btn link", type: "button", id: "forgotPasswordButton", onclick: async () => {
    error.hidden = true;
    if (!email.value.trim()) {
      error.textContent = "Enter your email above first.";
      error.hidden = false;
      return;
    }
    try {
      await sendPasswordResetEmail(auth, email.value.trim());
      // Worded the same whether or not the account exists, so this can't be
      // used to check which emails have accounts.
      note.textContent = "If there's an account for that email, a reset link is on its way.";
      note.hidden = false;
    } catch (e) {
      error.textContent = authMessage(e);
      error.hidden = false;
    }
  } }, "Forgot password?");

  const toggle = h("button", { class: "btn link", type: "button", id: "authToggleButton", onclick: () => {
    S.authMode = signup ? "signin" : "signup";
    renderAuth();
  } }, signup ? "Already have an account? Sign in" : "New here? Create an account");

  mount(h("div", { class: "stack" }, headerTop(),
    h("div", { class: "card stack" },
      h("h2", {}, signup ? "Create your account" : "Welcome back"),
      h("p", { class: "muted small" }, upgrading
        ? "Create an account to keep the pairing on this browser — then sign in with it on your phone and computer."
        : "Use the same account on your phone, your computer, and the iPhone app — you'll see the same countdown everywhere."),
      form, note,
      h("div", { class: "row spread" }, toggle, forgot))));
  (signup ? name : email).focus();
}

async function submitAuth({ name, email, password }, error, button) {
  if (S.authMode === "signup" && !name) {
    error.textContent = "Add the name your partner will see.";
    error.hidden = false;
    return;
  }
  S.authBusy = true;
  button.disabled = true;
  error.hidden = true;
  try {
    let user;
    if (S.authMode === "signup") {
      const current = auth.currentUser;
      // Captured before linking: Firebase mutates the user object in place,
      // so current.isAnonymous reads false once the link succeeds.
      const wasAnonymous = !!current?.isAnonymous;
      if (wasAnonymous) {
        // Upgrade in place: same uid, so a pre-accounts pairing carries over.
        user = (await linkWithCredential(current, EmailAuthProvider.credential(email, password))).user;
      } else {
        user = (await createUserWithEmailAndPassword(auth, email, password)).user;
      }
      const profile = { displayName: name };
      if (wasAnonymous && legacy.coupleId) profile.coupleId = legacy.coupleId;
      await makeApi(db, user.uid).saveProfile(profile);
      // Consumed: the next person to use this browser shouldn't see it.
      store.del("coupleId");
      store.del("displayName");
      legacy.coupleId = null;
      legacy.name = null;
    } else {
      user = (await signInWithEmailAndPassword(auth, email, password)).user;
    }
    S.authBusy = false;
    startSession(user);
  } catch (e) {
    console.error("Auth failed", e);
    S.authBusy = false;
    error.textContent = authMessage(e);
    error.hidden = false;
    button.disabled = false;
  }
}

function signOutButton() {
  return h("button", { class: "btn", id: "signOutButton", onclick: async () => {
    try {
      await signOut(auth);
    } catch (e) {
      console.error("Sign-out failed", e);
    }
  } }, "Sign out");
}

// ---------- onboarding ----------
function renderOnboarding() {
  S.screen = "onboarding";
  const views = { name: nameView, choice: choiceView, create: createView, join: joinView };
  mount(h("div", { class: "stack" }, headerTop(), views[S.step]()));
}

function nameView() {
  const input = h("input", { type: "text", id: "nameInput", placeholder: "Your name", autocomplete: "given-name", maxlength: "30" });
  const error = h("p", { class: "error", hidden: true });
  const go = h("button", { class: "btn primary", id: "continueButton", disabled: true, onclick: async () => {
    go.disabled = true;
    try {
      await S.api.saveProfile({ displayName: input.value.trim() });
    } catch (e) {
      console.error("saveProfile failed", e);
      error.textContent = friendly(e, "Couldn't save — try again.");
      error.hidden = false;
      go.disabled = false;
    }
  } }, "Continue");
  input.addEventListener("input", () => { go.disabled = !input.value.trim(); });
  input.addEventListener("keydown", (e) => { if (e.key === "Enter" && !go.disabled) go.click(); });
  return h("div", { class: "card stack" },
    h("h2", {}, "What should your partner see your name as?"),
    input, error, go);
}

function choiceView() {
  return h("div", { class: "card stack" },
    h("h2", {}, `Hi ${S.name} — let's get you two set up`),
    h("p", { class: "muted" }, "Only one of you should tap Create — have your partner tap Join with the code you'll get next. If you're already paired, sign in with that account instead."),
    h("button", { class: "btn primary", id: "createPairingButton", onclick: () => startCreate() }, "✨ Create a pairing"),
    h("button", { class: "btn", id: "joinPairingButton", onclick: () => { S.step = "join"; renderOnboarding(); } }, "💌 Join a pairing"),
    h("p", { class: "muted small" }, `Signed in as ${S.user?.email || ""}`),
    signOutButton(),
  );
}

async function startCreate() {
  if (S.creating) return;
  S.creating = true;
  S.createError = null;
  S.step = "create";
  renderOnboarding();
  try {
    // On success the account record gains the coupleId, and every signed-in
    // device (this one included) moves to the countdown, whose "waiting for
    // your partner" card shows the code to share.
    await S.api.createCouple(generateJoinCode(), S.name, timeZone());
  } catch (e) {
    console.error("createCouple failed", e);
    S.createError = friendly(e, "Couldn't create the pairing — try again.");
    if (S.screen !== "main") {
      S.step = "create";
      renderOnboarding();
    }
  }
  S.creating = false;
}

function createView() {
  if (S.createError) {
    return h("div", { class: "card stack" },
      h("p", { class: "error" }, S.createError),
      h("button", { class: "btn primary", onclick: () => startCreate() }, "Try again"),
      h("button", { class: "btn link", onclick: () => { S.createError = null; S.step = "choice"; renderOnboarding(); } }, "Back"));
  }
  return h("div", { class: "card center" }, h("p", { class: "muted" }, "Creating…"));
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
      S.prefillCode = "";
      // The account record now has the coupleId; its listener takes it from here.
    } catch (e) {
      console.error("joinCouple failed", e);
      // Deliberately generic: a wrong, already-full, cancelled, or expired
      // code all fail the Security Rules identically (permission denied).
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
  ["settings", "Settings"],
];

function enterMain() {
  S.screen = "main";
  S.tab = "home";
  S.couple = null;
  S.loadError = null;
  renderShell();
  listen();
}

function listen() {
  S.unsubCouple?.();
  S.unsubCouple = onSnapshot(
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
      if (S.tab === "home" || S.tab === "settings") renderTab();
    },
    (err) => {
      console.error("Couple listener failed", err);
      S.loadError = "This account can't open that pairing. Leave it to create or join a new one.";
      if (S.tab === "home" || S.tab === "settings") renderTab();
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
  const views = { home: homeView, dates: datesView, stats: statsView, settings: settingsView };
  content.replaceChildren(views[S.tab]());
  updateUnits();
}

// ---------- home ----------
function homeView() {
  if (S.loadError) {
    return h("div", { class: "card stack" }, h("p", { class: "error" }, S.loadError), leavePairingButton());
  }
  const c = S.couple;
  if (!c) return h("div", { class: "card center" }, h("p", { class: "muted" }, "Loading…"));

  const together = c.status === "together";
  const parts = [];

  if (c.participantUIDs.length < 2) parts.push(waitingCard());

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

// ---------- settings ----------
function settingsView() {
  const current = store.get("theme") || "blush";
  const swatches = THEMES.map((t) => h("button", { class: "swatch", id: `theme_${t.id}`, "aria-pressed": String(t.id === current), onclick: () => { applyTheme(t.id); renderTab(); } },
    h("span", { class: "dot", style: `background:${t.color}` }), `${t.emoji} ${t.name}`, t.id === current ? h("span", { style: "margin-left:auto" }, "✓") : null));
  const partner = S.couple
    ? Object.entries(S.couple.partnerProfiles).find(([uid]) => uid !== S.user?.uid)?.[1]?.displayName
    : null;
  return h("div", {},
    h("div", { class: "card stack" }, h("h2", {}, "Theme"), h("p", { class: "muted small" }, "Saved on this device."), h("div", { class: "swatches" }, swatches)),
    h("div", { class: "card stack" }, h("h2", {}, "Account"),
      h("p", { class: "muted small", id: "accountEmail" }, `Signed in as ${S.user?.email || ""}${S.name ? ` (${S.name})` : ""}.`),
      h("p", { class: "muted small" }, partner
        ? `Paired with ${partner}. Sign in with this account on any phone or computer to see the same countdown.`
        : "Sign in with this account on any phone or computer to see the same countdown."),
      signOutButton()));
}

function waitingCard() {
  const error = h("p", { class: "error", hidden: true });
  const cancel = h("button", { class: "btn link", id: "cancelPairingButton", onclick: async () => {
    if (!confirm("Cancel this pairing? Its code will stop working, and you can create a new one or join your partner's.")) return;
    cancel.disabled = true;
    try {
      await S.api.cancelPairing(S.coupleId);
    } catch (e) {
      console.error("cancelPairing failed", e);
      error.textContent = friendly(e, "Couldn't cancel — try again.");
      error.hidden = false;
      cancel.disabled = false;
    }
  } }, "Both tapped Create? Cancel this one");
  return h("div", { class: "card stack", id: "waitingCard" },
    h("h2", {}, "Waiting for your partner 💌"),
    h("div", { class: "code", id: "generatedCode" }, S.coupleId),
    shareButtons(S.coupleId),
    h("p", { class: "muted small" }, "Send this to your partner. They create their own account, tap “Join a pairing”, and enter it — on the web or in the iPhone app."),
    error, cancel);
}

function leavePairingButton() {
  return h("button", { class: "btn", id: "leavePairingButton", onclick: async () => {
    try {
      await S.api.forgetPairing();
    } catch (e) {
      console.error("forgetPairing failed", e);
    }
  } }, "Leave this pairing");
}

boot();
