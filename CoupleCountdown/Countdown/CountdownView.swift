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
            content
                .padding()
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
        .refreshable {
            await sync.fetchOnLaunch()
        }
        .task {
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
                    Task { await viewModel.toggleStatus(current: state.status, nextMeetupDate: state.nextMeetupDate) }
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

    private var datePromptSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Next meetup", selection: $pendingDate, displayedComponents: .date)
            }
            .navigationTitle("When do you leave?")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await viewModel.setNextMeetupDate(pendingDate, currentStatus: sync.state?.status ?? .together)
                        }
                    }
                }
            }
        }
    }
}
