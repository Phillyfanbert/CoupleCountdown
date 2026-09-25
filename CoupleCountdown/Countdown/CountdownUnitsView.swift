// CountdownUnitsView.swift — the live days / hours / minutes / seconds readout (DESIGN.md §6, §9)

import SwiftUI
import CoupleCountdownKit

/// Days, hours, minutes, and seconds left, redrawn every second by the
/// TimelineView around it. Replaces `Text(timerInterval:)`, which showed one
/// "171:23:45"-style string with no days.
struct CountdownUnitsView: View {
    let parts: CountdownFormatter.Parts
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            unit(parts.days, "days", id: "countdownDays", padded: false)
            unit(parts.hours, "hours", id: "countdownHours")
            unit(parts.minutes, "minutes", id: "countdownMinutes")
            unit(parts.seconds, "seconds", id: "countdownSeconds")
        }
        // .contain keeps each number's own identifier (an identifier on a
        // plain stack replaces its children's).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("countdownText")
    }

    private func unit(_ value: Int, _ label: String, id: String, padded: Bool = true) -> some View {
        VStack(spacing: 2) {
            Text(padded ? String(format: "%02d", value) : "\(value)")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: value)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityIdentifier(id)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
