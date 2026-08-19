// StatsView.swift — displays cumulative days together/apart (DESIGN.md §7.2)

import SwiftUI
import CoupleCountdownKit

struct StatsView: View {
    let coupleId: String
    @State private var stats: CumulativeStats?
    @State private var errorMessage: String?

    private let firestore = FirestoreService()

    var body: some View {
        VStack(spacing: 16) {
            if let stats {
                LabeledContent("Days together", value: stats.totalDaysTogether, format: .number.precision(.fractionLength(0)))
                LabeledContent("Days apart", value: stats.totalDaysApart, format: .number.precision(.fractionLength(0)))
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .padding()
        .navigationTitle("Stats")
        .task {
            await loadStats()
        }
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
