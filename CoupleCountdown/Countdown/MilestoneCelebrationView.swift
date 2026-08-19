// MilestoneCelebrationView.swift — confetti-style overlay for milestone moments (DESIGN.md §7.3)

import SwiftUI

struct MilestoneCelebrationView: View {
    let message: String
    var autoDismissDelay: Duration = .seconds(4)
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("🎉").font(.system(size: 56))
            Text(message)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(radius: 20)
        // Without this, the VStack stays transparent to accessibility and
        // only its Text children become elements — the identifier below
        // would attach to nothing queryable as a single unit.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("milestoneCelebration")
        .onTapGesture(perform: onDismiss)
        .task {
            try? await Task.sleep(for: autoDismissDelay)
            onDismiss()
        }
    }
}
