// StatsView.swift — displays cumulative days together/apart (DESIGN.md §7.2)

import SwiftUI
import CoupleCountdownKit

struct StatsView: View {
    let coupleId: String
    @State private var stats: CumulativeStats?
    @State private var errorMessage: String?

    @AppStorage("selectedTheme", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var selectedThemeRaw: String = CoupleTheme.blush.rawValue
    private var theme: CoupleTheme { CoupleTheme(rawValue: selectedThemeRaw) ?? .blush }

    private let firestore = FirestoreService()

    var body: some View {
        VStack(spacing: 20) {
            if let stats {
                statCard(icon: "heart.fill", label: "Days together", value: stats.totalDaysTogether)
                    .accessibilityIdentifier("daysTogetherStat")
                statCard(icon: "airplane", label: "Days apart", value: stats.totalDaysApart)
                    .accessibilityIdentifier("daysApartStat")
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .themedBackground()
        .navigationTitle("💞 Stats")
        .task {
            await loadStats()
        }
    }

    private func statCard(icon: String, label: String, value: Double) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(theme.accentColor)
                .frame(width: 36)
            Text(label)
                .font(.system(.body, design: .rounded))
            Spacer()
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.system(.title2, design: .rounded, weight: .bold))
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func loadStats() async {
        do {
            // Derived, not stored (§7.2) — walks the full event log
            // client-side rather than reading a precomputed value.
            let events = try await firestore.fetchEvents(coupleId: coupleId)
            stats = CumulativeStatsCalculator.calculate(events: events)
        } catch {
            errorMessage = "Couldn't load stats."
        }
    }
}
