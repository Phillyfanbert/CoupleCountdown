// DisplayNameEntryView.swift: first and last name, asked before Create/Join (DESIGN.md §5.3 point 2)

import SwiftUI
import UIKit
import CoupleCountdownKit

/// Shown to an account missing either name, including accounts made before
/// the last name was asked for. The first name is what the app calls you;
/// your partner sees both when confirming they're pairing with the right person.
struct DisplayNameEntryView: View {
    @Binding var firstName: String
    @Binding var lastName: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("💕")
                .font(.system(size: 64))

            Text("What's your name?")
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)

            Text("Your partner sees it when confirming they're pairing with you.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                nameField("First name", text: $firstName, contentType: .givenName)
                    .accessibilityIdentifier("nameTextField")
                nameField("Last name", text: $lastName, contentType: .familyName)
                    .accessibilityIdentifier("lastNameTextField")
            }
            .padding(.horizontal, 40)

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty ||
                    lastName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("continueButton")

            Spacer()
            Spacer()
        }
        .padding()
    }

    private func nameField(_ title: String, text: Binding<String>, contentType: UITextContentType) -> some View {
        TextField(title, text: text)
            .textContentType(contentType)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text.wrappedValue) { _, newName in
                if newName.count > PartnerProfile.maxNameLength {
                    text.wrappedValue = String(newName.prefix(PartnerProfile.maxNameLength))
                }
            }
            .font(.system(.body, design: .rounded))
            .multilineTextAlignment(.center)
    }
}
