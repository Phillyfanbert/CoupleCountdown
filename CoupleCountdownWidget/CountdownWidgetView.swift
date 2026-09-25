// CountdownWidgetView.swift — rendered widget content, including first-run/no-date empty states (DESIGN.md §6)

import SwiftUI
import WidgetKit
import CoupleCountdownKit

struct CountdownWidgetView: View {
    let entry: CountdownEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(spacing: 6) {
            countdown
            if let ping = entry.unseenPing, showsPing {
                Text("💌 " + ThinkingOfYouPing.headline(
                    senderName: entry.state?.partnerProfiles[ping.sentBy]?.displayName,
                    count: 1
                ))
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            }
        }
        // Required from iOS 17: without it the system shows "Please adopt
        // containerBackground API" in place of the widget. (Ignored on the
        // Lock Screen families, which draw their own background.)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "couplecountdown://open"))
    }

    /// Whole days as text (redrawn by the timeline entry at each day
    /// boundary) and the hours, minutes, and seconds of the current day as
    /// a live timer the system ticks by itself.
    @ViewBuilder
    private func countdownText(days: Int, timer: ClosedRange<Date>) -> some View {
        let dayLabel = days == 1 ? "1 day" : "\(days) days"
        switch family {
        case .accessoryInline:
            Text("\(days)d ") + Text(timerInterval: timer, countsDown: true)
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text("\(days)d").font(.system(.headline, design: .rounded))
                Text(timerInterval: timer, countsDown: true)
                    .font(.system(.caption2, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
            }
        default:
            VStack(spacing: 2) {
                Text(dayLabel)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(timerInterval: timer, countsDown: true)
                    .font(.system(.title3, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The circular and inline Lock Screen widgets have no room for a
    /// second line.
    private var showsPing: Bool {
        family != .accessoryCircular && family != .accessoryInline
    }

    @ViewBuilder
    private var countdown: some View {
        if let state = entry.state {
            // Same states as the app's countdown card: a timer only makes
            // sense while apart with the meetup still ahead — it used to
            // tick against the old date while together, too.
            if state.status == .together {
                Text("Together 💞")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
            } else if let nextMeetupDate = state.nextMeetupDate,
                      let day = CountdownFormatter.widgetDay(until: nextMeetupDate, from: entry.date) {
                countdownText(days: day.days, timer: entry.date...day.dayEnds)
            } else if state.nextMeetupDate != nil {
                // Countdown's done: ask, don't celebrate — the app celebrates
                // once someone says yes. Tapping opens the app to answer.
                Text(family == .accessoryInline ? "⏰ Have you met up?" : "⏰ Have you met up? 💞")
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
            } else {
                // No-date-set empty state applies right after pairing
                // too, not just the "leaving again" edge case (§6, §8).
                Text("Plan your next visit")
                    .font(.caption)
            }
        } else {
            // First-run empty state: no coupleId/cache yet (§6).
            Text("Not paired yet — open the app")
                .font(.caption)
        }
    }
}
