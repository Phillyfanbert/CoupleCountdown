// JoinPairingView.swift — code entry screen for the joining partner (DESIGN.md §5.3 point 4)

import SwiftUI

struct JoinPairingView: View {
    let displayName: String
    @Binding var coupleId: String

    @EnvironmentObject private var authService: AuthService
    @State private var enteredCode = ""
    @State private var errorMessage: String?
    @State private var isJoining = false

    private let firestore = FirestoreService()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "envelope.open.fill")
                .font(.system(size: 48))
                .foregroundStyle(CoupleTheme.blush.accentColor)

            Text("Enter your partner's code")
                .font(.system(.title3, design: .rounded, weight: .semibold))

            TextField("ABC123", text: $enteredCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title2, design: .monospaced, weight: .semibold))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 40)
                .accessibilityIdentifier("joinCodeTextField")

            if isJoining {
                ProgressView()
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
                    .accessibilityIdentifier("joinErrorText")
            }

            Button {
                Task { await join() }
            } label: {
                Label("Join", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .disabled(enteredCode.trimmingCharacters(in: .whitespaces).isEmpty || isJoining)
            .accessibilityIdentifier("joinButton")

            Spacer()
            Spacer()
        }
        .padding()
        .themedBackground()
    }

    private func join() async {
        guard let uid = authService.uid else {
            errorMessage = "Not signed in yet — try again in a moment."
            return
        }
        let code = enteredCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        isJoining = true
        do {
            try await firestore.joinCouple(
                coupleId: code,
                uid: uid,
                displayName: displayName,
                timeZoneIdentifier: TimeZone.current.identifier
            )
            coupleId = code
        } catch {
            // Deliberately generic — a wrong/expired/already-full code all
            // fail the Security Rules the same way (permission denied),
            // and DESIGN.md §5.3's rules don't distinguish those cases.
            errorMessage = "Couldn't join — check the code and try again."
        }
        isJoining = false
    }
}
