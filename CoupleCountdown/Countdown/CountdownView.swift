// CountdownView.swift — main countdown screen, status toggle, time zone display (DESIGN.md §8, §9, §9.1)

import SwiftUI
import CoupleCountdownKit

struct CountdownView: View {
    let coupleId: String
    let uid: String
    /// This person's name from their account — used to fill in their entry
    /// on the couple doc if a join's second write never landed.
    let displayName: String?

    @StateObject private var sync: SyncCoordinator
    @StateObject private var viewModel: CountdownViewModel
    @StateObject private var pings: PingInbox
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var celebrationMessage: String?
    /// The "have you met up?" alert, shown once per meetup on this device
    /// when its countdown runs out.
    @State private var isAskingMetUp = false
    @AppStorage("metUpAskedFor") private var metUpAskedFor: Double = 0
    @AppStorage("metUpNotYetFor") private var metUpNotYetFor: Double = 0
    @State private var isConfirmingCancel = false
    @State private var cancelError: String?
    @State private var leaveError: String?
    /// True while a status change runs, and for a second after: the main
    /// button swaps "We're together now" / "Leaving again" in place, so a
    /// double tap used to undo the change it had just made.
    @State private var isChangingStatus = false
    /// Every stretch apart, from the event log (and the pairing time).
    @State private var separations: [Separation] = []

    // Tracks which milestones have already been shown, so reopening the
    // app or the view reloading doesn't re-celebrate the same one every
    // time (DESIGN.md §7.3 never specified this, but the alternative —
    // celebrating "100 days!" on every launch — would be more annoying
    // than delightful).
    @AppStorage("celebratedMilestones", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var celebratedMilestonesRaw: String = ""

    @AppStorage("selectedTheme", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var selectedThemeRaw: String = CoupleTheme.blush.rawValue
    private var theme: CoupleTheme { CoupleTheme(rawValue: selectedThemeRaw) ?? .blush }

    private let firestore: FirestoreService

    init(coupleId: String, uid: String, displayName: String? = nil) {
        self.coupleId = coupleId
        self.uid = uid
        self.displayName = displayName
        let firestore = FirestoreService()
        self.firestore = firestore
        _sync = StateObject(wrappedValue: SyncCoordinator(
            firestore: firestore,
            cache: AppGroupCache(suiteName: SharedIdentifiers.appGroup),
            coupleId: coupleId,
            widgetKind: "CountdownWidget"
        ))
        _viewModel = StateObject(wrappedValue: CountdownViewModel(firestore: firestore, coupleId: coupleId, uid: uid))
        _pings = StateObject(wrappedValue: PingInbox(
            firestore: firestore,
            cache: AppGroupCache(suiteName: SharedIdentifiers.appGroup),
            coupleId: coupleId,
            uid: uid,
            widgetKind: "CountdownWidget"
        ))
    }

    var body: some View {
        NavigationStack {
            // Was a bare VStack, not a scrollable container — SwiftUI's
            // .refreshable gesture generally doesn't surface without a
            // List/ScrollView, so the manual pull-to-refresh fallback
            // (§5.2 mechanism #5) was effectively unreachable. Wrapping
            // in ScrollView fixes that without changing the layout for
            // content that fits on one screen.
            ScrollView {
                content
                    .padding()
                    .frame(maxWidth: .infinity)
            }
            .themedBackground()
            .refreshable {
                await sync.fetchOnLaunch()
            }
            .navigationTitle("💕 CoupleCountdown")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { StatsView(coupleId: coupleId, pairedAt: sync.state?.pairedAt) } label: {
                        Image(systemName: "chart.bar.fill")
                    }
                    .accessibilityIdentifier("statsNavLink")
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink {
                        CalendarScreen(coupleId: coupleId, partner: partnerProfile) { newState in
                            sync.applyLocalWrite(newState)
                        }
                    } label: {
                        Label("Calendar", systemImage: "calendar")
                    }
                    .accessibilityIdentifier("calendarNavLink")
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink { SettingsView() } label: {
                        Label("Settings", systemImage: "paintpalette.fill")
                    }
                    .accessibilityIdentifier("settingsNavLink")
                }
            }
        }
        .tint(theme.accentColor)
        .task {
            // Gated behind a launch argument only XCUITest ever passes —
            // real milestone triggering needs either elapsed real time or
            // a past nextMeetupDate, neither practical to arrange from a
            // UI test. This verifies the overlay itself (render, tap to
            // dismiss, auto-dismiss) actually works when wired up, which
            // is exactly the kind of thing that can silently break
            // (covered behind other content, gesture not registering)
            // without ever showing up in MilestoneChecker's own unit
            // tests, which only cover the detection logic in isolation.
            if ProcessInfo.processInfo.arguments.contains("-uiTestForceCelebration") {
                celebrationMessage = "Test celebration! 🎉"
            }
            // .onChange(of: scenePhase) below only fires on a transition,
            // never for the view's initial value — on a normal launch the
            // scene is already .active before this view ever appears, so
            // that "change" is never observed there. Starting the listener
            // here too is what actually makes §5.2 mechanism #1 (realtime
            // while both apps are open) engage on a fresh launch instead
            // of only after a background/foreground cycle.
            sync.startListening()
            pings.startListening()
            await sync.fetchOnLaunch()
            await syncOwnTimeZone()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                sync.startListening()
                pings.startListening()
                Task {
                    await sync.fetchOnLaunch()
                    await syncOwnTimeZone()
                }
            } else {
                sync.stopListening()
                pings.stopListening()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            Task { await syncOwnTimeZone() }
        }
        .onChange(of: sync.state) { oldState, newState in
            guard let newState else { return }
            // Your partner said you've met: the congratulations reach you too.
            if oldState?.status == .apart, newState.status == .together, newState.lastUpdatedBy != uid {
                celebrationMessage = CountdownFormatter.reunionMessage(
                    partnerName: newState.partnerProfiles[newState.lastUpdatedBy]?.displayName ?? "Your partner",
                    apartFor: ongoingSeparation?.duration()
                )
            }
            Task { await refreshHistory(state: newState) }
            Task { await ensureOwnProfile(state: newState) }
        }
        .task(id: arrivalWatchKey) {
            await askWhenCountdownEnds()
        }
        .alert("The countdown's done! ⏰", isPresented: $isAskingMetUp) {
            Button("Yes, we're together!") {
                Task { await confirmTogether() }
            }
            Button("Not yet", role: .cancel) {
                if let state = sync.state { metUpNotYetFor = meetupKey(state) }
            }
        } message: {
            Text("Have you two met up?")
        }
        .sheet(isPresented: Binding(
            get: { viewModel.visitSheetPurpose != nil },
            set: { if !$0 { viewModel.visitSheetPurpose = nil } }
        )) {
            visitSheet
        }
        .overlay {
            if let celebrationMessage {
                // Real users get the deliberately brief default (4s) —
                // under XCUITest that same window raced against real
                // network/automation overhead (app-idle waits, the
                // Firestore round-trip in refreshHistory) and the
                // overlay was reliably gone before a test ever got around
                // to checking for it. A longer delay only under the test
                // flag fixes the race without touching real UX timing.
                let arguments = ProcessInfo.processInfo.arguments
                let autoDismissDelay: Duration = arguments.contains("-uiTestForceCelebration") || arguments.contains("-uiTestLongCelebration")
                    ? .seconds(30) : .seconds(4)
                MilestoneCelebrationView(message: celebrationMessage, autoDismissDelay: autoDismissDelay) {
                    self.celebrationMessage = nil
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 20) {
            // "Keeping track of the current date": today, updated each minute.
            TimelineView(.everyMinute) { context in
                Text("Today is \(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("todayText")
            }

            if let state = sync.state {
                // What the partner sees when you tap "thinking of you" —
                // it used to be sent and never shown anywhere.
                if let newest = pings.unseen.first {
                    ReceivedPingCard(
                        pings: pings.unseen,
                        senderName: state.partnerProfiles[newest.sentBy]?.displayName,
                        accentColor: theme.accentColor,
                        onSendBack: {
                            try await firestore.sendPing(coupleId: coupleId, uid: uid)
                            try await pings.markAllSeen()
                        },
                        onDismiss: { try await pings.markAllSeen() }
                    )
                }
                if state.participantUIDs.count < 2 {
                    waitingForPartnerCard
                }
                // Redrawn every second: the digits stay current, and the card
                // switches to asking whether you've met the moment it ends.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdownCard(state: state, now: context.date)
                }
                statusBadge(state: state)
                // Each partner's local time, kept current (it used to be drawn
                // once and then sat frozen).
                TimelineView(.everyMinute) { context in
                    partnerTimeZones(state: state, now: context.date)
                }

                Button {
                    Task { await toggleStatus(state: state) }
                } label: {
                    Label(
                        state.status == .apart ? "We're together now" : "Leaving again",
                        systemImage: state.status == .apart ? "heart.fill" : "airplane.departure"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentColor)
                .controlSize(.large)
                .disabled(isChangingStatus)
                .accessibilityIdentifier("toggleStatusButton")

                ThinkingOfYouButton(coupleId: coupleId)
            } else if let problem = sync.loadProblem {
                loadProblemView(problem)
            } else {
                ProgressView("Loading…")
                    .padding(.top, 80)
                    .accessibilityIdentifier("countdownLoadingIndicator")
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }
        }
    }

    /// Shown until the partner joins. Before accounts, the code was only
    /// ever visible on the create screen — once past it, there was no way
    /// to see it again. Also where a mistaken pairing gets cancelled (the
    /// realistic case: both partners tapped Create).
    private var waitingForPartnerCard: some View {
        VStack(spacing: 12) {
            Text("Waiting for your partner 💌")
                .font(.headline)
            Text(coupleId)
                .font(.system(.title, design: .monospaced, weight: .bold))
                .textSelection(.enabled)
                .accessibilityIdentifier("waitingCodeText")
            ShareLink(item: JoinLink.url(for: coupleId), message: Text("Join me on CoupleCountdown with code \(coupleId)")) {
                Label("Share invite", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            Text("They create their own account, tap Join, and enter this — in the app or on the web.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let cancelError {
                Text(cancelError).font(.caption).foregroundStyle(.red)
            }
            Button("Both tapped Create? Cancel this one") {
                isConfirmingCancel = true
            }
            .font(.footnote)
            .accessibilityIdentifier("cancelPairingButton")
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        // .contain first: an identifier on a plain stack is pushed down onto
        // every child, replacing theirs — CI's accessibility snapshots showed
        // the code text and the cancel button both reporting
        // "waitingForPartnerCard", so waitingCodeText/cancelPairingButton
        // could never be found.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("waitingForPartnerCard")
        .confirmationDialog("Cancel this pairing?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
            Button("Cancel pairing", role: .destructive) {
                Task { await cancelPairing() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Its code will stop working, and you can create a new one or join your partner's.")
        }
    }

    /// The countdown couldn't load. It used to sit on "Loading…" for good,
    /// with no way to tell why and no way out.
    @ViewBuilder
    private func loadProblemView(_ problem: SyncCoordinator.LoadProblem) -> some View {
        VStack(spacing: 12) {
            Text(problem == .noAccess ? "This account can't open that pairing" : "Couldn't load your countdown")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("countdownLoadError")
            Text(problem == .noAccess
                 ? "Leave it to create a new pairing or join your partner's."
                 : "Check your connection and try again.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                sync.startListening()
                Task { await sync.fetchOnLaunch() }
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentColor)
            if problem == .noAccess {
                Button("Leave this pairing", role: .destructive) {
                    Task { await leaveUnreadablePairing() }
                }
                .accessibilityIdentifier("leavePairingButton")
            }
            if let leaveError {
                Text(leaveError).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.top, 60)
    }

    private func leaveUnreadablePairing() async {
        leaveError = nil
        do {
            // The account listener (AccountSessionView) then returns every
            // device on this account to onboarding.
            try await firestore.forgetPairing(uid: uid)
        } catch {
            leaveError = "Couldn't leave — check your connection and try again."
        }
    }

    private func cancelPairing() async {
        cancelError = nil
        do {
            // The account listener (AccountSessionView) returns every device
            // on this account to onboarding.
            try await firestore.cancelPairing(coupleId: coupleId, uid: uid)
        } catch {
            // The rules refuse to cancel once the partner has joined, so the
            // likely reason is that they just did.
            cancelError = "Couldn't cancel — your partner may have just joined. If not, check your connection and try again."
        }
    }

    @ViewBuilder
    private func countdownCard(state: RelationshipState, now: Date) -> some View {
        VStack(spacing: 8) {
            if state.status == .together {
                // Used to keep ticking "Until we're together again" against
                // the old date while they were in fact together.
                Text("💞").font(.largeTitle)
                Text("You're together")
                    .font(.headline)
                    .accessibilityIdentifier("togetherText")
                Text("Enjoy every minute.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let nextMeetupDate = state.nextMeetupDate,
                      let parts = CountdownFormatter.parts(until: nextMeetupDate, from: now) {
                Text("Until we're together again")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                CountdownUnitsView(parts: parts, accentColor: theme.accentColor)
                Text(nextMeetupDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("meetupTargetText")
                Button("Change date") { viewModel.visitSheetPurpose = .change }
                    .font(.footnote)
                    .accessibilityIdentifier("changeMeetupButton")
            } else if state.nextMeetupDate != nil {
                // The countdown's done. Ask before celebrating — it used to
                // celebrate the instant the timer hit zero, even if the
                // flight was late.
                let saidNotYet = metUpNotYetFor == meetupKey(state)
                Text("⏰").font(.largeTitle)
                Text("The countdown's done!")
                    .font(.headline)
                    .accessibilityIdentifier("countdownDoneText")
                Text("Have you two met up?")
                    .font(.subheadline)
                    .accessibilityIdentifier("metUpQuestionText")
                if saidNotYet {
                    Text("No rush. Tap Yes when you're together, or change the time if plans moved.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 8) {
                    Button {
                        Task { await confirmTogether() }
                    } label: {
                        Label("Yes, we're together!", systemImage: "heart.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accentColor)
                    .disabled(isChangingStatus)
                    .accessibilityIdentifier("metUpYesButton")
                    if saidNotYet {
                        Button("Change the time") { viewModel.visitSheetPurpose = .change }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("rescheduleButton")
                    } else {
                        Button("Not yet") { metUpNotYetFor = meetupKey(state) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("metUpNotYetButton")
                    }
                }
                .padding(.top, 4)
            } else {
                // No-date-set state applies immediately after pairing
                // too, not just the "leaving again" edge case (§6, §8).
                Image(systemName: "calendar.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(theme.accentColor)
                Text("No visit planned yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("noDateSetText")
                Button("Plan your next visit") { viewModel.visitSheetPurpose = .plan }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("planVisitButton")
            }
            // How long this stretch apart has lasted — the other half of
            // tracking the time from parting to being together again.
            if state.status == .apart, let since = ongoingSeparation?.start {
                Text("Apart for \(CountdownFormatter.durationLabel(now.timeIntervalSince(since))) so far")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                    .accessibilityIdentifier("apartForText")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: theme.accentColor.opacity(0.2), radius: 12, y: 6)
    }

    @ViewBuilder
    private func statusBadge(state: RelationshipState) -> some View {
        Label(
            state.status == .together ? "Together right now" : "Apart, for now",
            systemImage: state.status == .together ? "heart.fill" : "heart"
        )
        .font(.headline)
        .foregroundStyle(theme.accentColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(theme.accentColor.opacity(0.15), in: Capsule())
        .accessibilityIdentifier("statusBadge")
    }

    @ViewBuilder
    private func partnerTimeZones(state: RelationshipState, now: Date) -> some View {
        if !state.partnerProfiles.isEmpty {
            VStack(spacing: 4) {
                ForEach(Array(state.partnerProfiles.keys.sorted()), id: \.self) { profileUID in
                    if let profile = state.partnerProfiles[profileUID] {
                        Label(
                            CountdownFormatter.localTimeString(label: profile.displayName, timeZoneIdentifier: profile.timeZoneIdentifier, now: now),
                            systemImage: "clock.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The main button: "We're together now" or "Leaving again", depending
    /// on the status it shows. Each result is also applied to SyncCoordinator
    /// right away, so the acting partner's own widget updates without waiting
    /// for the listener (§5.2's sync pipeline convention).
    private func toggleStatus(state: RelationshipState) async {
        guard state.status == .together else {
            await confirmTogether()
            return
        }
        await changeStatus {
            // nil: the visit sheet opened (nothing planned), or it failed.
            guard let next = await viewModel.leave() else { return }
            var updated = state
            updated.status = .apart
            updated.nextMeetupDate = next
            updated.lastUpdatedBy = uid
            updated.lastUpdatedAt = Date()
            sync.applyLocalWrite(updated)
        }
    }

    /// "Yes, we're together!" and "We're together now". Only ever goes *to*
    /// together, from the latest state: the Yes buttons used to call the
    /// toggle, so a Yes tapped just after the partner's ran "Leaving again".
    private func confirmTogether() async {
        await changeStatus {
            guard let state = sync.state, state.status == .apart else { return }
            let apartFor = ongoingSeparation?.duration()
            sync.applyLocalWrite(await viewModel.markTogether(current: state))
            isAskingMetUp = false
            // Only now, once someone has said they've met.
            celebrationMessage = CountdownFormatter.reunionMessage(apartFor: apartFor)
        }
    }

    /// One status change at a time, and the buttons stay off for a second
    /// afterwards so a double tap can't land on the swapped button.
    private func changeStatus(_ change: () async -> Void) async {
        guard !isChangingStatus else { return }
        isChangingStatus = true
        await change()
        try? await Task.sleep(for: .seconds(1))
        isChangingStatus = false
    }

    /// The stretch apart still going on, if any.
    private var ongoingSeparation: Separation? {
        separations.last.flatMap { $0.end == nil ? $0 : nil }
    }

    /// The other partner's profile (name and time zone), once they've joined.
    private var partnerProfile: PartnerProfile? {
        sync.state?.partnerProfiles.first { $0.key != uid }?.value
    }

    @ViewBuilder
    private var visitSheet: some View {
        let purpose = viewModel.visitSheetPurpose
        VisitPlannerSheet(
            title: purpose == .change ? "Change the date ✈️" : "When do you see each other next? ✈️",
            // A meetup that has already passed (rescheduling after "not
            // yet") isn't a valid starting point: the picker only allows the future.
            initialStart: purpose == .change ? sync.state?.nextMeetupDate.flatMap { $0 > Date() ? $0 : nil } : nil,
            partner: partnerProfile,
            errorMessage: viewModel.errorMessage,
            onSave: { start, note in
                guard let state = sync.state,
                      let updated = await viewModel.saveVisit(start: start, note: note, current: state)
                else { return }
                sync.applyLocalWrite(updated)
            },
            onCancel: { viewModel.visitSheetPurpose = nil }
        )
    }

    /// A join whose second write failed leaves this person without a name
    /// on the couple doc (their partner sees no name or clock for them).
    private func ensureOwnProfile(state: RelationshipState) async {
        guard state.participantUIDs.contains(uid),
              state.partnerProfiles[uid] == nil,
              let displayName, !displayName.isEmpty
        else { return }
        try? await firestore.ensurePartnerProfile(
            coupleId: coupleId,
            uid: uid,
            displayName: displayName,
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
        )
    }

    /// Keeps this person's time zone on the couple doc current, so the
    /// partner's clock for them is right after they travel or move — it used
    /// to be written once, at pairing. Runs on launch, on coming back to the
    /// app, and when the phone's time zone changes; not on every update, so
    /// two of this person's devices in different zones can't keep
    /// overwriting each other.
    private func syncOwnTimeZone() async {
        guard let mine = sync.state?.partnerProfiles[uid] else { return }
        let zone = TimeZone.autoupdatingCurrent.identifier
        guard mine.timeZoneIdentifier != zone else { return }
        try? await firestore.ensurePartnerProfile(
            coupleId: coupleId,
            uid: uid,
            displayName: mine.displayName,
            timeZoneIdentifier: zone
        )
    }

    // MARK: - "Have you met up?" (§7.3)

    /// Identifies the meetup being counted down to, for remembering on this
    /// device that it was already asked about, or answered "not yet".
    private func meetupKey(_ state: RelationshipState) -> Double {
        state.nextMeetupDate?.timeIntervalSince1970 ?? 0
    }

    /// Restarts whenever the status or meetup changes.
    private var arrivalWatchKey: String {
        guard let state = sync.state, state.status == .apart, let meetup = state.nextMeetupDate else { return "none" }
        return "\(meetup.timeIntervalSince1970)"
    }

    /// Waits for the countdown to run out, then asks — once per meetup on
    /// this device. Also closes the question if the partner answers first.
    private func askWhenCountdownEnds() async {
        guard let state = sync.state, state.status == .apart, let meetup = state.nextMeetupDate else {
            isAskingMetUp = false
            return
        }
        let wait = meetup.timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait))
        }
        guard !Task.isCancelled, metUpAskedFor != meetupKey(state) else { return }
        metUpAskedFor = meetupKey(state)
        isAskingMetUp = true
    }

    // MARK: - History: stretches apart, milestones (§7.2, §7.3)

    /// Re-reads the event log after each change, for the stretches apart
    /// ("Apart for … so far", the reunion message) and round-number
    /// milestones.
    private func refreshHistory(state: RelationshipState) async {
        guard let events = try? await firestore.fetchEvents(coupleId: coupleId) else { return }
        separations = CumulativeStatsCalculator.separations(events: events, pairedAt: state.pairedAt)

        var celebrated = Set(celebratedMilestonesRaw.split(separator: ",").map(String.init))
        let stats = CumulativeStatsCalculator.calculate(events: events, pairedAt: state.pairedAt)
        if let milestone = MilestoneChecker.roundDayMilestoneReached(totalDaysTogether: stats.totalDaysTogether) {
            let key = "days-\(milestone)"
            if !celebrated.contains(key) {
                celebrated.insert(key)
                // Don't cover a reunion's congratulations.
                if celebrationMessage == nil {
                    celebrationMessage = "\(milestone) days together! 🎉"
                }
            }
        }
        celebratedMilestonesRaw = celebrated.joined(separator: ",")
    }
}
