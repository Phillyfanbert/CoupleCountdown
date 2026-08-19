// CountdownWidgetView.swift — rendered widget content, including first-run/no-date empty states (DESIGN.md §6)

import SwiftUI
import CoupleCountdownKit

struct CountdownWidgetView: View {
    let entry: CountdownEntry

    var body: some View {
        Group {
            if let state = entry.state {
                if let nextMeetupDate = state.nextMeetupDate {
                    Text(timerInterval: CountdownFormatter.timerInterval(to: nextMeetupDate), countsDown: true)
                        .font(.system(.title3, design: .rounded))
                } else {
                    // No-date-set empty state applies right after pairing
                    // too, not just the "leaving again" edge case (§6, §8)
                    // — reuses the same copy/UI intent as the app side.
                    Text("Add your next meetup date")
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
