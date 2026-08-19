// CountdownView.swift — main countdown screen, status toggle, time zone display (DESIGN.md §8, §9, §9.1)

import SwiftUI
import CoupleCountdownKit

struct CountdownView: View {
    let coupleId: String
    let uid: String

    @StateObject private var sync: SyncCoordinator
    @StateObject private var viewModel: CountdownViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var pendingDate = Date().addingTimeInterval(7 * 86_400)

    @AppStorage("selectedTheme", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var selectedThemeRaw: String = CoupleTheme.blush.rawValue
    private var theme: CoupleTheme { CoupleTheme(rawValue: selectedThemeRaw) ?? .blush }

    init(coupleId: String, uid: String) {
        self.coupleId = coupleId
        self.uid = uid
        let firestore = FirestoreService()
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
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink { ImportantDatesListView(coupleId: coupleId) } label: {
                        Label("Important Dates", systemImage: "calendar.badge.clock")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink { SettingsView() } label: {
                        Label("Settings", systemImage: "paintpalette.fill")
                    }
                }
            }
        }
        .tint(theme.accentColor)
        .task {
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
        .sheet(isPresented: $viewModel.promptForDate) {
            datePromptSheet
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 20) {
            if let state = sync.state {
                countdownCard(state: state)
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

                ThinkingOfYouButton(coupleId: coupleId)
            } else {
                ProgressView("Loading…")
                    .padding(.top, 80)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }
        }
    }

    @ViewBuilder
    private func countdownCard(state: RelationshipState) -> some View {
        VStack(spacing: 8) {
            if let nextMeetupDate = state.nextMeetupDate {
                Text("Until we're together again")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(timerInterval: CountdownFormatter.timerInterval(to: nextMeetupDate), countsDown: true)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            } else {
                // No-date-set state applies immediately after pairing
                // too, not just the "leaving again" edge case (§6, §8).
                Image(systemName: "calendar.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(theme.accentColor)
                Text("No date set yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
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

    /// Was previously just `Task { await viewModel.toggleStatus(...) }`
    /// with nothing done on success — the write reached Firestore but
    /// never reached SyncCoordinator, so the acting partner's own widget
    /// only updated once the realtime listener happened to echo the
    /// write back (a network round-trip §5.2 explicitly says shouldn't
    /// be needed for this exact case).
    private func toggleStatus(state: RelationshipState) async {
        let newStatus: RelationshipState.Status = state.status == .apart ? .together : .apart
        let succeeded = await viewModel.toggleStatus(current: state.status, nextMeetupDate: state.nextMeetupDate)
        guard succeeded else { return }
        var updated = state
        updated.status = newStatus
        updated.lastUpdatedBy = uid
        updated.lastUpdatedAt = Date()
        sync.applyLocalWrite(updated)
    }

    private var datePromptSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Next meetup", selection: $pendingDate, displayedComponents: .date)
                // Previously only shown in the underlying view, which is
                // covered while this sheet is presented — a save failure
                // here was invisible to the user.
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("When do you leave? ✈️")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveDate() }
                    }
                    .tint(theme.accentColor)
                }
            }
        }
    }

    private func saveDate() async {
        let succeeded = await viewModel.setNextMeetupDate(pendingDate, currentStatus: sync.state?.status ?? .together)
        guard succeeded, var updated = sync.state else { return }
        updated.status = .apart
        updated.nextMeetupDate = pendingDate
        updated.lastUpdatedBy = uid
        updated.lastUpdatedAt = Date()
        sync.applyLocalWrite(updated)
    }
}
