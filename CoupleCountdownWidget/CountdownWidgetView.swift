// CountdownWidgetView.swift — rendered widget content, including first-run/no-date empty states (DESIGN.md §6)

import SwiftUI
import CoupleCountdownKit

struct CountdownWidgetView: View {
    let entry: CountdownEntry

    var body: some View {
        Group {
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
        .widgetURL(URL(string: "couplecountdown://open"))
    }
}
