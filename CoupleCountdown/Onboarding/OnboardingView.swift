// OnboardingView.swift — Create/Join entry screen + display-name step (DESIGN.md §5.3 point 2)

import SwiftUI

struct OnboardingView: View {
    @Binding var coupleId: String

    @State private var displayName = ""
    @State private var didEnterName = false
    @State private var path: Path = .choice

    private enum Path {
        case choice
        case create
        case join
    }

    var body: some View {
        NavigationStack {
            Group {
                if !didEnterName {
                    DisplayNameEntryView(displayName: $displayName) {
                        didEnterName = true
                    }
                } else {
                    switch path {
                    case .choice:
                        choiceView
                    case .create:
                        CreatePairingView(displayName: displayName, coupleId: $coupleId)
                    case .join:
                        JoinPairingView(displayName: displayName, coupleId: $coupleId)
                    }
                }
            }
            .navigationTitle("CoupleCountdown")
        }
    }

    private var choiceView: some View {
        VStack(spacing: 20) {
            // Heads off the obvious failure mode (DESIGN.md §5.3 point 2)
            // — if both partners mistakenly tap Create, the result is
            // just two unused, self-cleaning couple docs, not corruption,
            // but the copy here is what's actually supposed to prevent it.
            Text("Only one of you should tap Create — have your partner tap Join with the code you'll get next.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Create a Pairing") { path = .create }
                .buttonStyle(.borderedProminent)

            Button("Join a Pairing") { path = .join }
                .buttonStyle(.bordered)
        }
        .padding()
    }
}
