// StatsView.swift — time together and apart, and each stretch apart (DESIGN.md §7.2)

import SwiftUI
import CoupleCountdownKit

struct StatsView: View {
    let coupleId: String
    /// When the pairing began — the start of the first stretch apart.
    let pairedAt: Date?

    @State private var stats: CumulativeStats?
    @State private var separations: [Separation] = []
    @State private var errorMessage: String?

    @AppStorage("selectedTheme", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var selectedThemeRaw: String = CoupleTheme.blush.rawValue
    private var theme: CoupleTheme { CoupleTheme(rawValue: selectedThemeRaw) ?? .blush }

    private let firestore = FirestoreService()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let stats {
                    statCard(icon: "heart.fill", label: "Days together", value: CountdownFormatter.statDays(stats.totalDaysTogether))
                        .accessibilityIdentifier("daysTogetherStat")
                    statCard(icon: "airplane", label: "Days apart", value: CountdownFormatter.statDays(stats.totalDaysApart))
                        .accessibilityIdentifier("daysApartStat")
                    separationCards
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else {
                    ProgressView()
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .themedBackground()
        .navigationTitle("💞 Stats")
        .refreshable { await loadStats() }
        .task {
            await loadStats()
        }
    }

    /// The time from parting to being together again, per stretch: the
    /// totals above alone never said how long any one separation lasted.
    @ViewBuilder
    private var separationCards: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 20) {
                if let current = separations.last, current.end == nil {
                    statCard(icon: "hourglass", label: "Apart right now", value: "\(CountdownFormatter.durationLabel(current.duration(now: context.date))) so far")
                        .accessibilityIdentifier("currentSeparationStat")
                }
                let finished = separations.filter { $0.end != nil }
                if let last = finished.last {
                    statCard(icon: "airplane.arrival", label: "Last time apart", value: CountdownFormatter.durationLabel(last.duration()))
                        .accessibilityIdentifier("lastSeparationStat")
                }
                if finished.count > 1, let longest = finished.map({ $0.duration() }).max() {
                    statCard(icon: "trophy.fill", label: "Longest apart", value: CountdownFormatter.durationLabel(longest))
                        .accessibilityIdentifier("longestSeparationStat")
                }
                if !finished.isEmpty {
                    statCard(icon: "sparkles", label: "Reunions", value: "\(finished.count)")
                        .accessibilityIdentifier("reunionsStat")
                }
            }
        }
    }

    private func statCard(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(theme.accentColor)
                .frame(width: 36)
            Text(label)
                .font(.system(.body, design: .rounded))
            Spacer()
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .multilineTextAlignment(.trailing)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // One element per row, so tests (and VoiceOver) read label and value together.
        .accessibilityElement(children: .combine)
    }

    private func loadStats() async {
        do {
            // Derived, not stored (§7.2) — walks the full event log
            // client-side rather than reading a precomputed value.
            let events = try await firestore.fetchEvents(coupleId: coupleId)
            stats = CumulativeStatsCalculator.calculate(events: events, pairedAt: pairedAt)
            separations = CumulativeStatsCalculator.separations(events: events, pairedAt: pairedAt)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load stats."
        }
    }
}
