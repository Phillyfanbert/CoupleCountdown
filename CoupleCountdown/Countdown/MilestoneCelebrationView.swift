// MilestoneCelebrationView.swift: confetti-style overlay for milestone moments (DESIGN.md §7.3)

import SwiftUI

struct MilestoneCelebrationView: View {
    let message: String
    var autoDismissDelay: Duration = .seconds(4)
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                ConfettiView()
            }
            VStack(spacing: 12) {
                Text("🎉").font(.system(size: 56))
                Text(message)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(radius: 20)
            .padding(24)
            // Without this, the VStack stays transparent to accessibility and
            // only its Text children become elements: the identifier below
            // would attach to nothing queryable as a single unit.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("milestoneCelebration")
            .onTapGesture(perform: onDismiss)
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear { appeared = true }
        .task {
            try? await Task.sleep(for: autoDismissDelay)
            onDismiss()
        }
    }
}

/// Hearts and sparkles falling past the celebration. Decorative only: it
/// never takes taps, and VoiceOver skips it.
private struct ConfettiView: View {
    private struct Piece {
        let emoji: String
        let x: CGFloat
        let delay: Double
        let spin: Double
    }

    @State private var pieces: [Piece] = (0..<28).map { index in
        Piece(
            emoji: ["🎉", "💕", "✨", "💞", "🥳", "💖"][index % 6],
            x: .random(in: 0.03...0.97),
            delay: .random(in: 0...0.9),
            spin: .random(in: -300...300)
        )
    }
    @State private var falling = false

    var body: some View {
        GeometryReader { geometry in
            ForEach(pieces.indices, id: \.self) { index in
                let piece = pieces[index]
                Text(piece.emoji)
                    .font(.title)
                    .rotationEffect(.degrees(falling ? piece.spin : 0))
                    .position(x: piece.x * geometry.size.width, y: falling ? geometry.size.height + 40 : -40)
                    .opacity(falling ? 0.3 : 1)
                    .animation(.easeIn(duration: 2.8).delay(piece.delay), value: falling)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { falling = true }
    }
}
