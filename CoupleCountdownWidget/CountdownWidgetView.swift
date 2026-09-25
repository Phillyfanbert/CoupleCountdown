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
            } else if let nextMeetupDate = state.nextMeetupDate, nextMeetupDate > entry.date {
                Text(timerInterval: CountdownFormatter.timerInterval(to: nextMeetupDate), countsDown: true)
                    .font(.system(.title3, design: .rounded))
            } else if state.nextMeetupDate != nil {
                Text("The day is here 🎉")
                    .font(.system(.headline, design: .rounded))
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
