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
            .themedBackground()
            .navigationTitle("💕 CoupleCountdown")
        }
        .tint(CoupleTheme.blush.accentColor)
    }

    private var choiceView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 56))
                .foregroundStyle(CoupleTheme.blush.accentColor)

            Text("Let's get you two set up")
                .font(.system(.title2, design: .rounded, weight: .semibold))

            // Heads off the obvious failure mode (DESIGN.md §5.3 point 2)
            // — if both partners mistakenly tap Create, the result is
            // just two unused, self-cleaning couple docs, not corruption,
            // but the copy here is what's actually supposed to prevent it.
            Text("Only one of you should tap Create — have your partner tap Join with the code you'll get next.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                Button {
                    path = .create
                } label: {
                    Label("Create a Pairing", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    path = .join
                } label: {
                    Label("Join a Pairing", systemImage: "envelope.open.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
        .padding()
    }
}
