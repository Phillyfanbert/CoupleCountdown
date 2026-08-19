// DisplayNameEntryView.swift — single display-name text field shown before Create/Join (DESIGN.md §5.3 point 2)

import SwiftUI

struct DisplayNameEntryView: View {
    @Binding var displayName: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("What should your partner see your name as?")
                .font(.headline)
                .multilineTextAlignment(.center)
            TextField("Your name", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }
}
