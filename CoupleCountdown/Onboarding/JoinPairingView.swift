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
        VStack(spacing: 16) {
            Text("Enter your partner's code")
                .font(.headline)
            TextField("ABC123", text: $enteredCode)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal)

            if isJoining {
                ProgressView()
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }

            Button("Join") {
                Task { await join() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(enteredCode.trimmingCharacters(in: .whitespaces).isEmpty || isJoining)
        }
        .padding()
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
