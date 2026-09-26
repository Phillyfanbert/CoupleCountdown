// DisplayNameEntryView.swift: single display-name text field shown before Create/Join (DESIGN.md §5.3 point 2)

import SwiftUI
import CoupleCountdownKit

struct DisplayNameEntryView: View {
    @Binding var displayName: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("💕")
                .font(.system(size: 64))

            Text("What should your partner\nsee your name as?")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)

            TextField("Your name", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: displayName) { _, newName in
                    if newName.count > PartnerProfile.maxNameLength {
                        displayName = String(newName.prefix(PartnerProfile.maxNameLength))
                    }
                }
                .font(.system(.body, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .accessibilityIdentifier("nameTextField")

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("continueButton")

            Spacer()
            Spacer()
        }
        .padding()
    }
}
