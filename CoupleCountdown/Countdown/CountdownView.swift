// CountdownView.swift — main countdown screen, status toggle, time zone display (DESIGN.md §8, §9, §9.1)

import SwiftUI
import CoupleCountdownKit

struct CountdownView: View {
    let coupleId: String
    let uid: String

    @StateObject private var sync: SyncCoordinator
    @StateObject private var viewModel: CountdownViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingDate = Date().addingTimeInterval(7 * 86_400)

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
            .refreshable {
                await sync.fetchOnLaunch()
            }
            .navigationTitle("CoupleCountdown")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink("Stats") { StatsView(coupleId: coupleId) }
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink("Important Dates") { ImportantDatesListView(coupleId: coupleId) }
                }
                ToolbarItem(placement: .secondaryAction) {
                    NavigationLink("Settings") { SettingsView() }
                }
            }
        }
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
        VStack(spacing: 24) {
            if let state = sync.state {
                if let nextMeetupDate = state.nextMeetupDate {
                    Text(timerInterval: CountdownFormatter.timerInterval(to: nextMeetupDate), countsDown: true)
                        .font(.system(.largeTitle, design: .rounded))
                        .contentTransition(.numericText())
                } else {
                    // No-date-set state applies immediately after pairing
                    // too, not just the "leaving again" edge case (§6, §8).
                    Text("No date set yet")
                        .foregroundStyle(.secondary)
                }

                Text(state.status == .together ? "Together" : "Apart")
                    .font(.headline)

                ForEach(Array(state.partnerProfiles.keys.sorted()), id: \.self) { profileUID in
                    if let profile = state.partnerProfiles[profileUID] {
                        Text(CountdownFormatter.localTimeString(label: profile.displayName, timeZoneIdentifier: profile.timeZoneIdentifier))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button(state.status == .apart ? "We're together now" : "Leaving again") {
                    Task { await toggleStatus(state: state) }
                }
                .buttonStyle(.borderedProminent)

                ThinkingOfYouButton(coupleId: coupleId)
            } else {
                ProgressView("Loading…")
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
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
            .navigationTitle("When do you leave?")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveDate() }
                    }
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
