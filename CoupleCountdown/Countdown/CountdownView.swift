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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var celebrationMessage: String?
    @State private var isConfirmingCancel = false
    @State private var cancelError: String?

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
                    NavigationLink { StatsView(coupleId: coupleId) } label: {
                        Image(systemName: "chart.bar.fill")
                    }
                    .accessibilityIdentifier("statsNavLink")
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink {
                        CalendarScreen(coupleId: coupleId) { newState in
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
            await sync.fetchOnLaunch()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                sync.startListening()
                Task { await sync.fetchOnLaunch() }
            } else {
                sync.stopListening()
            }
        }
        .onChange(of: sync.state) { _, newState in
            guard let newState else { return }
            Task { await checkForMilestones(state: newState) }
            Task { await ensureOwnProfile(state: newState) }
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
                // Firestore round-trip in checkForMilestones) and the
                // overlay was reliably gone before a test ever got around
                // to checking for it. A longer delay only under the test
                // flag fixes the race without touching real UX timing.
                let autoDismissDelay: Duration = ProcessInfo.processInfo.arguments.contains("-uiTestForceCelebration") ? .seconds(30) : .seconds(4)
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
                if state.participantUIDs.count < 2 {
                    waitingForPartnerCard
                }
                // Re-evaluated every 30s so the card switches from the
                // countdown to "the day is here" when the meetup arrives.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    countdownCard(state: state, now: context.date)
                }
                statusBadge(state: state)
                partnerTimeZones(state: state)

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
                .accessibilityIdentifier("toggleStatusButton")

                ThinkingOfYouButton(coupleId: coupleId)
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
            ShareLink(item: coupleId, message: Text("Join me on CoupleCountdown with code \(coupleId)")) {
                Label("Share code", systemImage: "square.and.arrow.up")
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
            } else if let nextMeetupDate = state.nextMeetupDate, nextMeetupDate > now {
                Text("Until we're together again")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(timerInterval: CountdownFormatter.timerInterval(to: nextMeetupDate), countsDown: true)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityIdentifier("countdownText")
                Text(nextMeetupDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("meetupTargetText")
                Button("Change date") { viewModel.visitSheetPurpose = .change }
                    .font(.footnote)
                    .accessibilityIdentifier("changeMeetupButton")
            } else if state.nextMeetupDate != nil {
                Text("🎉").font(.largeTitle)
                Text("The day is here")
                    .font(.headline)
                    .accessibilityIdentifier("dayIsHereText")
                Text("Tap “We're together now” when you meet — or pick a new date if plans changed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Pick a new date") { viewModel.visitSheetPurpose = .plan }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("planVisitButton")
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
    private func partnerTimeZones(state: RelationshipState) -> some View {
        if !state.partnerProfiles.isEmpty {
            VStack(spacing: 4) {
                ForEach(Array(state.partnerProfiles.keys.sorted()), id: \.self) { profileUID in
                    if let profile = state.partnerProfiles[profileUID] {
                        Label(
                            CountdownFormatter.localTimeString(label: profile.displayName, timeZoneIdentifier: profile.timeZoneIdentifier),
                            systemImage: "clock.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Also applies the result to SyncCoordinator right away, so the acting
    /// partner's own widget updates without waiting for the listener to echo
    /// the write back (§5.2's sync pipeline convention).
    private func toggleStatus(state: RelationshipState) async {
        var updated = state
        if state.status == .apart {
            guard await viewModel.markTogether() else { return }
            updated.status = .together
        } else {
            // nil means the visit sheet opened (nothing planned) or it failed.
            guard let next = await viewModel.leave() else { return }
            updated.status = .apart
            updated.nextMeetupDate = next
        }
        updated.lastUpdatedBy = uid
        updated.lastUpdatedAt = Date()
        sync.applyLocalWrite(updated)
    }

    @ViewBuilder
    private var visitSheet: some View {
        let purpose = viewModel.visitSheetPurpose
        VisitPlannerSheet(
            title: purpose == .change ? "Change the date ✈️" : "When do you see each other next? ✈️",
            initialStart: purpose == .change ? sync.state?.nextMeetupDate : nil,
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
            timeZoneIdentifier: TimeZone.current.identifier
        )
    }

    // MARK: - Milestone celebration (§7.3)

    private func checkForMilestones(state: RelationshipState) async {
        var celebrated = Set(celebratedMilestonesRaw.split(separator: ",").map(String.init))

        if MilestoneChecker.countdownReachedZero(nextMeetupDate: state.nextMeetupDate, status: state.status) {
            let key = "zero-\(Int(state.nextMeetupDate?.timeIntervalSince1970 ?? 0))"
            if !celebrated.contains(key) {
                celebrated.insert(key)
                celebrationMessage = "You're together again! 🎉"
            }
        }

        if let events = try? await firestore.fetchEvents(coupleId: coupleId) {
            let stats = CumulativeStatsCalculator.calculate(events: events)
            if let milestone = MilestoneChecker.roundDayMilestoneReached(totalDaysTogether: stats.totalDaysTogether) {
                let key = "days-\(milestone)"
                if !celebrated.contains(key) {
                    celebrated.insert(key)
                    // Only overwrite the countdown-reached-zero message if
                    // that one didn't already fire this pass — both firing
                    // at once is an edge case not worth stacking UI for.
                    if celebrationMessage == nil {
                        celebrationMessage = "\(milestone) days together! 🎉"
                    }
                }
            }
        }

        celebratedMilestonesRaw = celebrated.joined(separator: ",")
    }
}
