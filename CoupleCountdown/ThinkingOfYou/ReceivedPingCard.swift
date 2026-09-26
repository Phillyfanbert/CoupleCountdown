// ReceivedPingCard.swift: shows the partner's "thinking of you" on the countdown screen (DESIGN.md §7.1)

import SwiftUI
import CoupleCountdownKit

/// "💌 Sam is thinking of you · 2 hours ago", with a way to send one back
/// or dismiss it. Stays until one of those, on any of this person's devices.
struct ReceivedPingCard: View {
    /// The partner's unseen pings, newest first (non-empty).
    let pings: [ThinkingOfYouPing]
    let senderName: String?
    let accentColor: Color
    let onSendBack: () async throws -> Void
    let onDismiss: () async throws -> Void

    @State private var isWorking = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 10) {
            Text("💌")
                .font(.largeTitle)
            Text(ThinkingOfYouPing.headline(senderName: senderName, count: pings.count))
                .font(.system(.headline, design: .rounded))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("receivedPingText")
            if let newest = pings.first {
                // Redrawn each minute, so "2 hours ago" doesn't go stale.
                TimelineView(.everyMinute) { _ in
                    Text(newest.sentAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button {
                    run(onSendBack)
                } label: {
                    Label("Send one back", systemImage: "heart.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .accessibilityIdentifier("pingSendBackButton")

                Button("Dismiss") {
                    run(onDismiss)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pingDismissButton")
            }
            .disabled(isWorking)
            if failed {
                Text("Couldn't update. Check your connection and try again.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        // .contain, so the text and buttons keep their own identifiers (an
        // identifier on a plain stack replaces its children's).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("receivedPingCard")
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            isWorking = true
            failed = false
            do {
                try await action()
            } catch {
                failed = true
            }
            isWorking = false
        }
    }
}
