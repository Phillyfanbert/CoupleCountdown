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
  defaultVisitStart,
  durationLabel,
  formatStatDays,
  localISODate,
  localTimeLabel,
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
  timeAgo,
  unseenPings,
  visitMetEarly,
  zonedTime,
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
  plan: { visits: [], dates: [], loaded: false, error: null }, // visits + important dates
  calMonth: null, // { y, m } shown on the Calendar tab
  calSelected: null, // "YYYY-MM-DD" selected on the Calendar tab
  pings: { all: [], dismissed: new Set(), unseen: [], error: null }, // the partner's "thinking of you"s
  // Per meetup (its time in ms) on this device: already asked "have you met
  // up?", and answered "not yet". Kept in memory too, in case storage is blocked.
  metUp: { asked: store.get("metUpAskedFor"), notYet: store.get("metUpNotYetFor") },
  unsubProfile: null,
  unsubCouple: null,
  unsubPings: null,
  // Every stretch apart ({ start, end }), from the event log and pairing time.
  history: { separations: [], loaded: false },
  zoneSynced: false, // this session already brought our time zone up to date
  metUpClose: null, // closes the "have you met up?" popup, while it's open
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
  stopCoupleListeners();
  Object.assign(S, { unsubProfile: null, user: null, api: null, name: "", coupleId: "", couple: null, loadError: null });
}

function stopCoupleListeners() {
  S.unsubCouple?.();
  S.unsubPings?.();
  S.unsubCouple = null;
  S.unsubPings = null;
  S.pings = { all: [], dismissed: new Set(), unseen: [], error: null };
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
  S.name = p.displayName || "";
  if (p.coupleId) {
    if (p.coupleId !== S.coupleId || S.screen !== "main") {
      S.coupleId = p.coupleId;
      enterMain();
    }
    return;
  }
  S.coupleId = "";
  stopCoupleListeners();
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
      h("p", { class: `small ${upgrading && !signup ? "error" : "muted"}`, id: "authIntro" }, upgrading
        ? signup
          ? "Create an account to keep the pairing on this browser — then sign in with it on your phone and computer."
          // Signing in replaces the old identity, and a pairing's members
          // can't change afterwards — so that pairing would be lost for good.
          : "This browser has a pairing from before accounts. Signing in to an existing account leaves it behind for good — create an account instead to keep it."
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

/**
 * A button for an action whose failure must not look like nothing happened
 * (sign-out and leaving used to fail silently): it says so on the button.
 */
function actionButton(id, label, failedLabel, action) {
  const button = h("button", { class: "btn", id, onclick: async () => {
    button.disabled = true;
    try {
      await action();
      button.textContent = label;
    } catch (e) {
      console.error(`${id} failed`, e);
      button.textContent = failedLabel;
    }
    button.disabled = false;
  } }, label);
  return button;
}

function signOutButton() {
  return actionButton("signOutButton", "Sign out", "Couldn't sign out — tap to try again", () => signOut(auth));
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
  ["calendar", "Calendar"],
  ["stats", "Stats"],
  ["settings", "Settings"],
];

function enterMain() {
  S.screen = "main";
  S.tab = "home";
  S.couple = null;
  S.loadError = null;
  S.plan = { visits: [], dates: [], loaded: false, error: null };
  S.history = { separations: [], loaded: false };
  S.zoneSynced = false;
  renderShell();
  listen();
  listenPings();
  loadPlan();
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
        const previousStatus = S.couple?.status;
        if (previousStatus === "apart" && d.status === "together" && d.lastUpdatedBy !== S.user?.uid) {
          const name = d.partnerProfiles?.[d.lastUpdatedBy]?.displayName || "Your partner";
          celebrate(reunionMessage(name, ongoingApartMs()));
        }
        S.couple = {
          status: d.status,
          nextMeetupDate: d.nextMeetupDate?.toDate?.() ?? null,
          participantUIDs: d.participantUIDs || [],
          partnerProfiles: d.partnerProfiles || {},
          pairedAt: d.pairedAt?.toDate?.() ?? null,
        };
        S.loadError = null;
        ensureOwnProfile();
        if (!S.zoneSynced) {
          S.zoneSynced = true;
          syncOwnTimeZone();
        }
        if (previousStatus !== d.status) loadHistory();
        // The partner answered "have you met up?" first: close the question here.
        if (countdownState(S.couple) !== "arrived") closeMetUpQuestion();
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

/** The partner's pings, live — it's how "thinking of you" reaches them. */
function listenPings() {
  S.unsubPings?.();
  S.pings = { all: [], dismissed: new Set(), unseen: [], error: null };
  S.unsubPings = S.api.watchRecentPings(S.coupleId, (pings) => {
    S.pings.all = pings;
    refreshPings();
  }, (e) => console.error("Ping listener failed", e));
}

function refreshPings() {
  const unseen = unseenPings(S.pings.all, S.user?.uid).filter((p) => !S.pings.dismissed.has(p.id));
  const changed = unseen.map((p) => p.id).join() !== S.pings.unseen.map((p) => p.id).join();
  S.pings.unseen = unseen;
  if (changed && S.screen === "main" && S.tab === "home") renderTab();
}

/** Dismisses what the card shows, on every device on this account. Hidden here straight away. */
async function dismissPings() {
  const ids = S.pings.unseen.map((p) => p.id);
  ids.forEach((id) => S.pings.dismissed.add(id));
  S.pings.error = null;
  refreshPings();
  try {
    await S.api.markPingsSeen(S.coupleId, ids);
  } catch (e) {
    ids.forEach((id) => S.pings.dismissed.delete(id));
    throw e;
  }
}

/** The stretches apart, re-read whenever the status changes. */
async function loadHistory() {
  try {
    const events = await S.api.fetchEvents(S.coupleId);
    S.history = { separations: separations(events, S.couple?.pairedAt), loaded: true };
  } catch (e) {
    console.error("loadHistory failed", e);
    return;
  }
  if (S.screen === "main" && S.tab === "home") renderTab();
}

/** The stretch apart still going on, if any. */
function ongoingSeparation() {
  const last = S.history.separations.at(-1);
  return last && !last.end ? last : null;
}

function ongoingApartMs() {
  const sep = ongoingSeparation();
  return sep ? Date.now() - sep.start : null;
}

/** The other partner's profile (name and time zone), once they've joined. */
function partnerProfile() {
  return Object.entries(S.couple?.partnerProfiles || {}).find(([uid]) => uid !== S.user?.uid)?.[1] ?? null;
}

/**
 * Keeps this person's time zone on the couple doc current, so the partner's
 * clock for them is right after they travel or move — it used to be written
 * once, at pairing. Runs when the pairing opens and when the tab comes back
 * into view; not on every update, so two of this person's devices in
 * different zones can't keep overwriting each other.
 */
function syncOwnTimeZone() {
  const mine = S.couple?.partnerProfiles[S.user?.uid];
  if (!mine || mine.timeZoneIdentifier === timeZone()) return;
  S.api.ensurePartnerProfile(S.coupleId, mine.displayName, timeZone()).catch((e) => console.error("syncOwnTimeZone failed", e));
}
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && S.screen === "main") syncOwnTimeZone();
});

/** A join whose second write failed leaves this person nameless on the couple doc. */
function ensureOwnProfile() {
  const c = S.couple;
  if (!c || !S.name || !c.participantUIDs.includes(S.user?.uid) || c.partnerProfiles[S.user.uid]) return;
  S.api.ensurePartnerProfile(S.coupleId, S.name, timeZone()).catch((e) => console.error("ensurePartnerProfile failed", e));
}

/** Visits and important dates, shared by the countdown's "Coming up" and the Calendar tab. */
async function loadPlan() {
  try {
    const [visits, dates] = await Promise.all([S.api.fetchVisits(S.coupleId), S.api.fetchImportantDates(S.coupleId)]);
    S.plan = { visits, dates, loaded: true, error: null };
  } catch (e) {
    console.error("loadPlan failed", e);
    S.plan = { ...S.plan, loaded: true, error: "Couldn't load your plans — switch tabs to try again." };
  }
  if (S.screen === "main" && (S.tab === "home" || S.tab === "calendar")) renderTab();
}

function renderShell() {
  const nav = h("nav", { class: "tabs" }, TABS.map(([id, label]) =>
    h("button", { "data-tab": id, "aria-current": S.tab === id ? "page" : null, onclick: () => {
      S.tab = id;
      renderShell();
      if (id === "home" || id === "calendar") loadPlan();
    } }, label)));
  mount(h("div", { class: `shell tab-${S.tab}` }, headerTop(), nav, h("div", { id: "content" })));
  renderTab();
}

function renderTab() {
  const content = document.getElementById("content");
  if (!content) return;
  const views = { home: homeView, calendar: calendarView, stats: statsView, settings: settingsView };
  content.replaceChildren(views[S.tab]());
  tick();
}

// ---------- home ----------
function homeView() {
  if (S.loadError) {
    return h("div", { class: "card stack" }, h("p", { class: "error" }, S.loadError), leavePairingButton());
  }
  const c = S.couple;
  if (!c) return h("div", { class: "card center" }, h("p", { class: "muted" }, "Loading…"));

  const together = c.status === "together";
  const main = [];

  // "Keeping track of the current date" — refreshed by tick().
  main.push(h("p", { class: "today muted", id: "todayText" }, todayLabel()));

  if (S.pings.unseen.length) main.push(pingCard(c));
  if (c.participantUIDs.length < 2) main.push(waitingCard());

  main.push(countdownCard(c));
  main.push(h("div", { class: "row spread", style: "margin-bottom:16px" },
    h("span", { class: "badge", id: "statusBadge" }, together ? "❤️ Together right now" : "🤍 Apart, for now")));

  // Kept current by tick() — it used to be drawn once and then sat frozen.
  if (Object.keys(c.partnerProfiles).length) main.push(h("p", { class: "muted small", id: "clocks" }, clockLabels(c)));

  const error = h("p", { class: "error", id: "homeError", hidden: true });
  const toggle = h("button", {
    class: "btn primary",
    id: "toggleStatusButton",
    disabled: S.busy,
    onclick: () => (S.couple?.status === "together" ? leaveAgain() : confirmTogether()),
  }, together ? "✈️ Leaving again" : "❤️ We're together now");
  const ping = h("button", { class: "btn", id: "thinkingOfYouButton", onclick: () => onPing(ping, error) }, "💌 Send a little “thinking of you”");
  main.push(h("div", { class: "stack" }, toggle, ping, error));

  // On a wide screen "Coming up" sits beside the countdown; on a phone, below it.
  return h("div", { class: "columns" },
    h("div", { class: "col-main" }, main),
    h("div", { class: "col-side" }, comingUpCard({ limit: 5 })));
}

/** "💌 Sam is thinking of you · 2 hours ago" — until dismissed or answered. */
function pingCard(c) {
  const newest = S.pings.unseen[0];
  const act = async (fn) => {
    back.disabled = dismiss.disabled = true;
    try {
      await fn();
    } catch (e) {
      console.error("ping action failed", e);
      S.pings.error = "Couldn't update — check your connection and try again.";
    }
    refreshPings();
    renderTab();
  };
  const back = h("button", { class: "btn primary", id: "pingSendBackButton", onclick: () => act(async () => {
    await S.api.sendPing(S.coupleId);
    await dismissPings();
  }) }, "💕 Send one back");
  const dismiss = h("button", { class: "btn", id: "pingDismissButton", onclick: () => act(dismissPings) }, "Dismiss");
  return h("div", { class: "card stack ping-card", id: "receivedPingCard" },
    h("div", { class: "empty-big" }, "💌"),
    h("h2", { id: "receivedPingText" }, pingHeadline(c.partnerProfiles[newest.sentBy]?.displayName, S.pings.unseen.length)),
    h("p", { class: "muted small", id: "receivedPingTime" }, timeAgo(newest.sentAt)),
    h("div", { class: "row" }, back, dismiss),
    S.pings.error ? h("p", { class: "error" }, S.pings.error) : null);
}

function clockLabels(c, now = new Date()) {
  return Object.values(c.partnerProfiles).map((p) => localTimeLabel(p.displayName, p.timeZoneIdentifier, now)).join("  ·  ");
}

/** "Apart for 23 days so far" — how long this stretch apart has lasted (kept current by tick()). */
function apartLine(c) {
  const sep = c.status === "apart" ? ongoingSeparation() : null;
  if (!sep) return null;
  return h("p", { class: "muted small", id: "apartForText", style: "margin-top:12px" }, `Apart for ${durationLabel(Date.now() - sep.start)} so far`);
}

function todayLabel(now = new Date()) {
  return `Today is ${now.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}`;
}

/** Which of the four countdown states applies right now. */
function countdownState(c, now = new Date()) {
  if (c.status === "together") return "together";
  if (!c.nextMeetupDate) return "none";
  return c.nextMeetupDate > now ? "counting" : "arrived";
}

function countdownCard(c) {
  const state = countdownState(c);
  const card = (...kids) => h("div", { class: "card countdown", "data-state": state }, ...kids, apartLine(c));
  if (state === "together") {
    // Previously the iPhone kept ticking "until we're together again" here.
    return card(h("div", { class: "empty-big" }, "💞"), h("h2", { id: "togetherText" }, "You're together"), h("p", { class: "muted" }, "Enjoy every minute."));
  }
  if (state === "none") {
    return card(h("div", { class: "empty-big" }, "🗓️"), h("h2", { id: "noDateText" }, "No visit planned yet"), h("p", { class: "muted" }, "When do you see each other next?"), planButton("Plan your next visit", "plan"));
  }
  if (state === "arrived") {
    // The countdown's done: ask before celebrating — a late flight shouldn't
    // get congratulations.
    const key = meetupKey(c);
    const notYet = S.metUp.notYet === key;
    return card(
      h("div", { class: "empty-big" }, "⏰"),
      h("h2", { id: "countdownDoneText" }, "The countdown's done!"),
      h("p", { id: "metUpQuestionText" }, "Have you two met up?"),
      notYet ? h("p", { class: "muted small" }, "No rush. Tap Yes when you're together, or change the time if plans moved.") : null,
      h("div", { class: "stack", style: "margin-top:12px" },
        h("button", { class: "btn primary", id: "metUpYesButton", disabled: S.busy, onclick: confirmTogether }, "💞 Yes, we're together!"),
        notYet
          ? h("button", { class: "btn", id: "rescheduleButton", onclick: () => openVisitModal("change") }, "Change the time")
          : h("button", { class: "btn", id: "metUpNotYetButton", onclick: () => { rememberMetUp("notYet", key); renderTab(); } }, "Not yet")));
  }
  return card(
    h("div", { class: "label" }, "Until we're together again"),
    h("div", { class: "units", id: "units" },
      ["days", "hours", "minutes", "seconds"].map((u) => h("div", { class: "unit" }, h("b", { id: `u-${u}` }, "–"), h("span", {}, u)))),
    h("p", { class: "muted small target", id: "meetupTargetText" }, formatWhen(c.nextMeetupDate)),
    h("button", { class: "btn link", id: "changeMeetupButton", onclick: () => openVisitModal("change") }, "Change date"));
}

function planButton(label, purpose) {
  return h("button", { class: "btn", id: "planVisitButton", style: "margin-top:12px", onclick: () => openVisitModal(purpose) }, label);
}

/** "Thu, Oct 1 at 6:30 PM" — in the viewer's own time, or in `timeZone`. */
function formatWhen(date, timeZone = undefined) {
  const day = date.toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric", timeZone });
  const time = date.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit", timeZone });
  return `${day} at ${time}`;
}

/** Runs every second: countdown digits, today's date, and switching cards when the meetup arrives. */
function tick() {
  const today = document.getElementById("todayText");
  if (today) today.textContent = todayLabel();
  const c = S.couple;
  if (!c || S.tab !== "home") return;
  const clocks = document.getElementById("clocks");
  if (clocks) clocks.textContent = clockLabels(c);
  const pingTime = document.getElementById("receivedPingTime");
  if (pingTime && S.pings.unseen[0]) pingTime.textContent = timeAgo(S.pings.unseen[0].sentAt);
  const apart = document.getElementById("apartForText");
  const sep = ongoingSeparation();
  if (apart && sep) apart.textContent = `Apart for ${durationLabel(Date.now() - sep.start)} so far`;
  const card = document.querySelector(".card.countdown");
  if (card && card.dataset.state !== countdownState(c)) {
    renderTab();
    askIfMetUp();
    return;
  }
  if (card?.dataset.state === "arrived") askIfMetUp();
  if (!document.getElementById("units")) return;
  const p = countdownParts(c.nextMeetupDate);
  if (!p) return;
  for (const u of ["days", "hours", "minutes", "seconds"]) {
    const el = document.getElementById(`u-${u}`);
    if (el) el.textContent = String(p[u]).padStart(u === "days" ? 1 : 2, "0");
  }
}
setInterval(tick, 1000);

/**
 * "We're together now" / "Yes, we're together!". Only ever goes *to*
 * together, from the latest state. Meeting before the planned time moves that
 * visit to now, so "Leaving again" can't count down to it a second time.
 */
async function confirmTogether() {
  if (S.couple?.status !== "apart") return;
  await changeStatus(async () => {
    const c = S.couple;
    if (c?.status !== "apart") return;
    const apartFor = ongoingApartMs();
    const now = normalizedStart(new Date());
    let metEarly = null;
    if (c.nextMeetupDate && c.nextMeetupDate > now) {
      try {
        metEarly = visitMetEarly(c.nextMeetupDate, await S.api.fetchVisits(S.coupleId), now);
      } catch (e) {
        console.error("fetchVisits failed; not moving the visit", e);
      }
    }
    watchSave(S.api.setStatus(S.coupleId, "together", metEarly ? now : null, metEarly ? { id: metEarly.id, start: now } : null));
    closeMetUpQuestion();
    // Only now, once someone has said they've met.
    celebrate(reunionMessage(null, apartFor));
  });
}

/** Every goodbye is a new trip: count down to the next *planned* visit, or ask for one if nothing is planned. */
async function leaveAgain() {
  await changeStatus(async () => {
    const next = nextUpcoming(await S.api.fetchVisits(S.coupleId));
    if (next) watchSave(S.api.setStatus(S.coupleId, "apart", next.start));
    else openVisitModal("leaving");
  });
}

/**
 * One status change at a time; the buttons stay off for a second after, so
 * a double tap can't land on the button that just swapped its label.
 */
async function changeStatus(change) {
  if (S.busy) return;
  S.busy = true;
  setStatusButtonsDisabled(true);
  showHomeError(null);
  try {
    await change();
  } catch (e) {
    console.error("status change failed", e);
    showHomeError("Couldn't update — check your connection and try again.");
  }
  setTimeout(() => {
    S.busy = false;
    setStatusButtonsDisabled(false);
  }, 1000);
}

/** The write goes out without waiting (offline, it's sent later); a rejection is still reported. */
function watchSave(saving) {
  saving.catch((e) => {
    console.error("status write failed", e);
    showHomeError("Couldn't save that change — check your connection and try again.");
  });
}

function showHomeError(text) {
  const el = document.getElementById("homeError");
  if (!el) return;
  el.textContent = text || "";
  el.hidden = !text;
}

function setStatusButtonsDisabled(disabled) {
  document.querySelectorAll("#toggleStatusButton, #metUpYesButton, #metUpModalYesButton").forEach((b) => { b.disabled = disabled; });
}

// ---------- "have you met up?" and the celebration ----------
const meetupKey = (c) => String(c.nextMeetupDate?.getTime() ?? "");

function rememberMetUp(field, key) {
  S.metUp[field] = key;
  store.set(field === "asked" ? "metUpAskedFor" : "metUpNotYetFor", key);
}

/** When the countdown runs out, ask once per meetup on this device. The card keeps asking after that. */
function askIfMetUp() {
  const c = S.couple;
  if (!c || countdownState(c) !== "arrived") return;
  const key = meetupKey(c);
  if (S.metUp.asked === key || document.querySelector(".modal-backdrop")) return;
  rememberMetUp("asked", key);
  S.metUpClose = openModal("The countdown's done! ⏰", "Have you met up?",
    h("p", {}, "Have you two met up?"),
    h("button", { class: "btn primary", id: "metUpModalYesButton", onclick: () => { closeMetUpQuestion(); confirmTogether(); } }, "💞 Yes, we're together!"),
    h("button", { class: "btn", id: "metUpModalNotYetButton", onclick: () => { closeMetUpQuestion(); rememberMetUp("notYet", key); renderTab(); } }, "Not yet"));
}

function closeMetUpQuestion() {
  S.metUpClose?.();
  S.metUpClose = null;
}

/** Congratulations with falling hearts; tap it or wait a few seconds to close. */
function celebrate(message) {
  document.getElementById("celebration")?.remove();
  const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const pieces = calm ? [] : Array.from({ length: 28 }, (_, i) => h("span", {
    class: "confetti",
    "aria-hidden": "true",
    style: `left:${(3 + Math.random() * 94).toFixed(1)}%;animation-delay:${(Math.random() * 0.9).toFixed(2)}s;--spin:${Math.round(Math.random() * 600 - 300)}deg`,
  }, ["🎉", "💕", "✨", "💞", "🥳", "💖"][i % 6]));
  const overlay = h("div", { class: "celebration", id: "celebration", role: "status", onclick: () => overlay.remove() },
    pieces,
    h("div", { class: "celebration-card" }, h("div", { class: "empty-big" }, "🎉"), h("h2", { id: "celebrationText" }, message)));
  document.body.append(overlay);
  setTimeout(() => overlay.remove(), 5000);
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

// ---------- modals ----------
function openModal(title, label, ...content) {
  const backdrop = h("div", { class: "modal-backdrop", onclick: (e) => { if (e.target === backdrop) backdrop.remove(); } },
    h("div", { class: "modal stack", role: "dialog", "aria-modal": "true", "aria-label": label }, h("h2", {}, title), ...content));
  document.body.append(backdrop);
  return () => backdrop.remove();
}

/**
 * Plan a visit — a date *and time*, so the countdown ends when you actually
 * meet (it used to end at midnight in whoever set it's time zone).
 *   leaving: "Leaving again" with nothing planned — also switches to apart.
 *   plan:    fill a missing or passed meetup.
 *   change:  replace the meetup currently counted down to.
 *   calendar: from the Calendar tab; the countdown follows the earliest plan.
 */
function openVisitModal(purpose, initial = null) {
  const current = S.couple?.nextMeetupDate ?? null;
  const start = initial ?? (purpose === "change" && current && current > new Date() ? current : defaultVisitStart());
  const date = h("input", { type: "date", id: "visitDateInput", value: localISODate(start), min: localISODate(new Date()) });
  const time = h("input", { type: "time", id: "visitTimeInput", value: `${String(start.getHours()).padStart(2, "0")}:${String(start.getMinutes()).padStart(2, "0")}` });
  const note = h("input", { type: "text", id: "visitNoteInput", placeholder: "Note (optional) — e.g. Sam lands at LAX", maxlength: "80" });
  // With the partner in another time zone, the time can be entered as theirs.
  // It used to be read silently in this browser's zone, so a traveler
  // entering the landing time at the other end ended the countdown hours off.
  const partner = partnerProfile();
  const partnerZone = partner && partner.timeZoneIdentifier !== timeZone() ? partner.timeZoneIdentifier : null;
  const zone = partnerZone
    ? h("select", { id: "visitZoneInput", onchange: () => updateSummary() },
      h("option", { value: "mine" }, "My time"),
      h("option", { value: "partner" }, `${partner.displayName}'s time`))
    : null;
  const summary = partnerZone ? h("p", { class: "muted small", id: "visitZoneSummary" }) : null;
  const pickedTime = () => {
    if (!date.value || !time.value) return null;
    const [y, mo, d] = date.value.split("-").map(Number);
    const [hh, mm] = time.value.split(":").map(Number);
    if (zone?.value === "partner") return zonedTime(y, mo, d, hh, mm, partnerZone);
    const local = parseLocalISODate(date.value);
    local.setHours(hh, mm, 0, 0);
    return local;
  };
  // The same moment for both of them, so a mix-up shows before saving.
  const updateSummary = () => {
    if (!summary) return;
    const at = pickedTime();
    summary.textContent = at ? `For you: ${formatWhen(at)} · For ${partner.displayName}: ${formatWhen(at, partnerZone)}` : "";
  };
  date.addEventListener("input", updateSummary);
  time.addEventListener("input", updateSummary);
  const error = h("p", { class: "error", hidden: true });
  const save = h("button", { class: "btn primary", id: "saveDateButton", onclick: async () => {
    const picked = pickedTime();
    if (!picked) return;
    if (picked <= new Date()) {
      error.textContent = "Pick a time in the future.";
      error.hidden = false;
      return;
    }
    save.disabled = true;
    error.hidden = true;
    try {
      await saveVisit(purpose, picked, note.value.trim());
      close();
    } catch (e) {
      console.error("saveVisit failed", e);
      error.textContent = "Couldn't save the visit — check your connection and try again.";
      error.hidden = false;
      save.disabled = false;
    }
  } }, "Save");
  const title = purpose === "change" ? "Change the date ✈️" : purpose === "calendar" ? "Plan a visit ✈️" : "When do you see each other next? ✈️";
  const close = openModal(title, "Plan a visit",
    h("div", { class: "row" }, h("label", { class: "field grow" }, "Date", date), h("label", { class: "field grow" }, "Time", time)),
    zone ? h("label", { class: "field" }, "Whose time?", zone) : null,
    summary,
    h("label", { class: "field" }, "Note", note),
    error, save,
    h("button", { class: "btn link", onclick: () => close() }, "Cancel"));
  updateSummary();
  date.focus();
}

async function saveVisit(purpose, start, note) {
  const current = S.couple?.nextMeetupDate ?? null;
  const visit = await S.api.addVisit(S.coupleId, { start, note });
  let visits = await S.api.fetchVisits(S.coupleId);
  if (purpose === "leaving") {
    await S.api.setStatus(S.coupleId, "apart", nextUpcoming(visits)?.start ?? visit.start);
  } else {
    if (purpose === "change" && current) {
      // Replace the visit the countdown pointed at (if it was one).
      const replaced = visits.find((v) => v.id !== visit.id && Math.abs(v.start - current) < 1000);
      if (replaced) {
        await S.api.deleteVisit(S.coupleId, replaced.id);
        visits = visits.filter((v) => v.id !== replaced.id);
      }
    }
    const resolved = resolvedNextMeetup(purpose === "change" ? null : current, visits);
    if ((resolved?.getTime() ?? null) !== (current?.getTime() ?? null)) await S.api.setNextMeetupDate(S.coupleId, resolved);
  }
  await loadPlan();
}

async function deleteVisit(visit) {
  if (!confirm("Delete this visit?")) return;
  try {
    await S.api.deleteVisit(S.coupleId, visit.id);
    const visits = S.plan.visits.filter((v) => v.id !== visit.id);
    const current = S.couple?.nextMeetupDate ?? null;
    const resolved = resolvedNextMeetup(current, visits, visit);
    if ((resolved?.getTime() ?? null) !== (current?.getTime() ?? null)) await S.api.setNextMeetupDate(S.coupleId, resolved);
  } catch (e) {
    console.error("deleteVisit failed", e);
    alert("Couldn't delete — check your connection and try again.");
  }
  await loadPlan();
}

function openImportantDateModal(initialDay = null) {
  const label = h("input", { type: "text", id: "dateLabelInput", placeholder: "Label (e.g. Anniversary)", maxlength: "60" });
  const date = h("input", { type: "date", id: "importantDateInput", value: localISODate(initialDay ?? new Date()) });
  const repeats = h("input", { type: "checkbox", id: "repeatsAnnuallyInput", checked: true });
  const error = h("p", { class: "error", hidden: true });
  const save = h("button", { class: "btn primary", id: "saveImportantDateButton", disabled: true, onclick: async () => {
    if (!label.value.trim() || !date.value) return;
    save.disabled = true;
    error.hidden = true;
    try {
      await S.api.addImportantDate(S.coupleId, { label: label.value.trim(), day: parseLocalISODate(date.value), repeatsAnnually: repeats.checked });
      close();
      await loadPlan();
    } catch (e) {
      console.error("addImportantDate failed", e);
      error.textContent = "Couldn't save — check your connection and try again.";
      error.hidden = false;
      save.disabled = false;
    }
  } }, "Save");
  label.addEventListener("input", () => { save.disabled = !label.value.trim(); });
  const close = openModal("Add an important date 🎁", "Add an important date",
    label,
    h("label", { class: "field" }, "Date", date),
    h("label", { class: "check" }, repeats, "Repeats every year"),
    error, save,
    h("button", { class: "btn link", onclick: () => close() }, "Cancel"));
  label.focus();
}

async function deleteImportantDate(item) {
  if (!confirm(`Delete “${item.label}”?`)) return;
  try {
    await S.api.deleteImportantDate(S.coupleId, item.id);
  } catch (e) {
    console.error("deleteImportantDate failed", e);
    alert("Couldn't delete — check your connection and try again.");
  }
  await loadPlan();
}

// ---------- plan: agenda + calendar ----------

/** Upcoming visits and dates (soonest first), and past ones (most recent first). */
function agenda(now = new Date()) {
  const visits = S.plan.visits.map((v) => ({ kind: "visit", item: v, when: v.start }));
  const dates = S.plan.dates.map((d) => ({ kind: "date", item: d, when: nextOccurrence(d.date, d.repeatsAnnually, now) }));
  const all = [...visits, ...dates];
  const isUpcoming = (e) => (e.kind === "visit" ? e.when > now : daysUntil(e.when, now) >= 0);
  return {
    upcoming: all.filter(isUpcoming).sort((a, b) => a.when - b.when),
    // Past one-off dates used to sort *above* upcoming ones.
    past: all.filter((e) => !isUpcoming(e)).sort((a, b) => b.when - a.when).slice(0, 10),
  };
}

function agendaRow(entry) {
  const n = daysUntil(entry.when);
  if (entry.kind === "visit") {
    const v = entry.item;
    return h("li", { class: "visit", "data-visit": v.id },
      h("div", {}, h("div", {}, `✈️ ${v.note || "Visit"}`), h("div", { class: "when" }, formatWhen(v.start))),
      h("div", { class: "row" }, h("span", { class: "until" }, relativeDayLabel(n)),
        h("button", { class: "icon-btn", "aria-label": "Delete visit", onclick: () => deleteVisit(v) }, "×")));
  }
  const d = entry.item;
  return h("li", { "data-label": d.label },
    h("div", {}, h("div", {}, `${d.repeatsAnnually ? "🎁" : "⭐"} ${d.label}`),
      h("div", { class: "when" }, entry.when.toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" }))),
    h("div", { class: "row" }, h("span", { class: "until" }, relativeDayLabel(n)),
      h("button", { class: "icon-btn", "aria-label": `Delete ${d.label}`, onclick: () => deleteImportantDate(d) }, "×")));
}

function comingUpCard({ limit = Infinity } = {}) {
  const { upcoming } = agenda();
  let body;
  if (!S.plan.loaded) body = h("p", { class: "muted" }, "Loading…");
  else if (S.plan.error) body = h("p", { class: "error" }, S.plan.error);
  else if (!upcoming.length) body = h("p", { class: "muted", id: "noDatesText" }, "Nothing yet — plan your next visit, or add your anniversary.");
  else body = h("ul", { class: "list", id: "comingUpList" }, upcoming.slice(0, limit).map(agendaRow));
  return h("div", { class: "card", id: "comingUpCard" },
    h("div", { class: "row spread" }, h("h2", {}, "📅 Coming up"),
      limit !== Infinity ? h("button", { class: "btn link", onclick: () => { S.tab = "calendar"; renderShell(); loadPlan(); } }, "Calendar →") : null),
    body);
}

function calendarView() {
  const now = new Date();
  const month = S.calMonth ?? { y: now.getFullYear(), m: now.getMonth() };
  const cells = monthCells(month.y, month.m);
  const visitDays = new Set(S.plan.visits.map((v) => localISODate(v.start)));
  const importantOn = (d, year) => (d.repeatsAnnually || d.date.getFullYear() === year ? localISODate(new Date(year, d.date.getMonth(), d.date.getDate())) : null);
  const dateDays = new Set(S.plan.dates.map((d) => importantOn(d, month.y)).filter(Boolean));
  const todayKey = localISODate(now);

  const shiftMonth = (delta) => {
    const d = new Date(month.y, month.m + delta, 1);
    S.calMonth = { y: d.getFullYear(), m: d.getMonth() };
    renderTab();
  };
  const header = h("div", { class: "row spread cal-header" },
    h("button", { class: "icon-btn", "aria-label": "Previous month", id: "previousMonthButton", onclick: () => shiftMonth(-1) }, "‹"),
    h("h2", { id: "calendarMonthTitle" }, new Date(month.y, month.m, 1).toLocaleDateString(undefined, { month: "long", year: "numeric" })),
    h("button", { class: "icon-btn", "aria-label": "Next month", id: "nextMonthButton", onclick: () => shiftMonth(1) }, "›"));
  const weekdays = ["S", "M", "T", "W", "T", "F", "S"].map((w) => h("div", { class: "cal-weekday" }, w));
  const days = cells.map((day) => {
    if (!day) return h("div", { class: "cal-cell empty" });
    const key = localISODate(day);
    const marks = [visitDays.has(key) ? "visit planned" : null, dateDays.has(key) ? "important date" : null].filter(Boolean);
    return h("button", {
      class: `cal-cell${key === todayKey ? " today" : ""}${S.calSelected === key ? " selected" : ""}`,
      id: `calendarDay_${key}`,
      "aria-label": [day.toLocaleDateString(undefined, { month: "long", day: "numeric" }), key === todayKey ? "today" : null, ...marks].filter(Boolean).join(", "),
      "aria-pressed": String(S.calSelected === key),
      onclick: () => { S.calSelected = S.calSelected === key ? null : key; renderTab(); },
    }, h("span", {}, String(day.getDate())),
      h("span", { class: "dots" }, visitDays.has(key) ? h("i", { class: "dot-visit" }) : null, dateDays.has(key) ? h("i", { class: "dot-date" }) : null));
  });
  const grid = h("div", { class: "card" }, header, h("div", { class: "cal-grid" }, weekdays, days),
    h("p", { class: "muted small legend" }, h("i", { class: "dot-visit" }), " visit  ", h("i", { class: "dot-date" }), " important date"));

  const selected = S.calSelected ? parseLocalISODate(S.calSelected) : null;
  const selectedFuture = selected && selected >= new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const actions = h("div", { class: "row" },
    h("button", { class: "btn primary", id: "planVisitFromCalendarButton", onclick: () => {
      let initial = null;
      if (selectedFuture) { initial = new Date(selected); initial.setHours(18, 0, 0, 0); if (initial <= now) initial = null; }
      openVisitModal("calendar", initial);
    } }, "✈️ Plan a visit"),
    h("button", { class: "btn", id: "addImportantDateButton", onclick: () => openImportantDateModal(selected) }, "🎁 Add a date"));

  const side = [];
  if (selected) {
    const onDay = [...agenda().upcoming, ...agenda().past].filter((e) =>
      (e.kind === "visit" ? localISODate(e.item.start) : importantOn(e.item, selected.getFullYear())) === S.calSelected);
    side.push(h("div", { class: "card" }, h("h2", {}, selected.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })),
      onDay.length ? h("ul", { class: "list" }, onDay.map(agendaRow)) : h("p", { class: "muted" }, "Nothing planned")));
  }
  side.push(comingUpCard());
  const { past } = agenda();
  if (past.length) {
    side.push(h("details", { class: "card-details" }, h("summary", {}, `Past (${past.length})`), h("ul", { class: "list" }, past.map(agendaRow))));
  }
  return h("div", { class: "columns" },
    h("div", { class: "col-main" }, grid, actions),
    h("div", { class: "col-side" }, side));
}

// ---------- stats ----------
function statsView() {
  const body = h("div", { class: "stack" }, h("p", { class: "muted" }, "Loading…"));
  (async () => {
    try {
      const events = await S.api.fetchEvents(S.coupleId);
      const pairedAt = S.couple?.pairedAt ?? null;
      const stats = computeStats(events, new Date(), pairedAt);
      const stretches = separations(events, pairedAt);
      const finished = stretches.filter((sep) => sep.end);
      const current = stretches.at(-1)?.end === null ? stretches.at(-1) : null;
      const row = (id, label, value) => h("div", { class: "stat", id }, h("span", {}, label), h("b", {}, value));
      if (!body.isConnected) return;
      body.replaceChildren(
        row("daysTogetherStat", "❤️ Days together", formatStatDays(stats.totalDaysTogether)),
        row("daysApartStat", "✈️ Days apart", formatStatDays(stats.totalDaysApart)),
        // How long each stretch apart lasted — the totals alone never said.
        current ? row("currentSeparationStat", "⏳ Apart right now", `${durationLabel(Date.now() - current.start)} so far`) : null,
        finished.length ? row("lastSeparationStat", "🛬 Last time apart", durationLabel(finished.at(-1).end - finished.at(-1).start)) : null,
        finished.length > 1 ? row("longestSeparationStat", "🏆 Longest apart", durationLabel(Math.max(...finished.map((sep) => sep.end - sep.start)))) : null,
        finished.length ? row("reunionsStat", "✨ Reunions", String(finished.length)) : null);
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
      // The rules refuse to cancel once the partner has joined, so that's the
      // likely reason.
      error.textContent = friendly(e, "Couldn't cancel — your partner may have just joined. If not, try again.");
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
  return actionButton("leavePairingButton", "Leave this pairing", "Couldn't leave — check your connection and tap to try again", () => S.api.forgetPairing());
}

boot();
