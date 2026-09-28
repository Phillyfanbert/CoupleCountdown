// JoinPairingView.swift: code entry and "Pair with Alex Smith?" confirmation for the joining partner (DESIGN.md §5.3 point 4)

import SwiftUI
import CoupleCountdownKit

struct JoinPairingView: View {
    let displayName: String
    let lastName: String?
    /// This person's own unused code, when both of them tapped Create:
    /// joining the partner's discards it in the same save.
    var ownCode: String? = nil
    let onBack: () -> Void

    @EnvironmentObject private var authService: AuthService
    @State private var enteredCode = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    /// Whose pairing the code is, awaiting the person's confirmation.
    @State private var preview: FirestoreService.JoinPreview?

    private let firestore = FirestoreService()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "envelope.open.fill")
                .font(.system(size: 48))
                .foregroundStyle(CoupleTheme.blush.accentColor)

            Text("Enter your partner's code")
                .font(.system(.title3, design: .rounded, weight: .semibold))

            if let ownCode {
                Text("Your own code, \(ownCode), stops working once you join theirs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            TextField("ABC123", text: $enteredCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title2, design: .monospaced, weight: .semibold))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 40)
                .accessibilityIdentifier("joinCodeTextField")

            if isWorking {
                ProgressView()
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("joinErrorText")
            }

            Button {
                Task { await lookUp() }
            } label: {
                Label("Join", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .disabled(code.isEmpty || isWorking)
            .accessibilityIdentifier("joinButton")

            Button("Back", action: onBack)
                .font(.footnote)
                .accessibilityIdentifier("joinBackButton")

            Spacer()
            Spacer()
        }
        .padding()
        .themedBackground()
        // Shows whose code it is before pairing, so nobody pairs with the
        // wrong person by a mistyped or mixed-up code.
        .alert(
            "Pair with \(preview?.partnerName ?? "your partner")?",
            isPresented: Binding(get: { preview != nil }, set: { if !$0 { preview = nil } }),
            presenting: preview
        ) { preview in
            Button("Pair") { Task { await requestToJoin(preview) } }
            Button("Cancel", role: .cancel) {}
        } message: { preview in
            Text("Only pair if \(preview.partnerName) is your partner. They'll be asked to approve, then you'll share one countdown and calendar.")
        }
    }

    private var code: String {
        enteredCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Finds whose code it is, for the confirmation.
    private func lookUp() async {
        guard let uid = authService.uid else {
            errorMessage = "Not signed in yet. Try again in a moment."
            return
        }
        errorMessage = nil
        isWorking = true
        do {
            preview = try await firestore.joinPreview(coupleId: code, uid: uid)
        } catch FirestoreService.JoinPreviewProblem.notFound {
            errorMessage = "There's no open pairing with that code. Check it with your partner."
        } catch FirestoreService.JoinPreviewProblem.cancelled {
            errorMessage = "That code was cancelled. Ask your partner for their current one."
        } catch FirestoreService.JoinPreviewProblem.ownCode {
            errorMessage = "That's your own code. Send it to your partner instead."
        } catch FirestoreService.JoinPreviewProblem.anotherRequestWaiting {
            errorMessage = "Someone else is already waiting for approval on that code. Check it with your partner."
        } catch {
            errorMessage = "Couldn't check the code. Check your connection and try again."
        }
        isWorking = false
    }

    /// Pairing takes both people: this asks, and the creator approves.
    private func requestToJoin(_ preview: FirestoreService.JoinPreview) async {
        guard let uid = authService.uid else { return }
        errorMessage = nil
        isWorking = true
        do {
            try await firestore.requestToJoin(
                coupleId: preview.coupleId,
                uid: uid,
                displayName: displayName,
                lastName: lastName,
                timeZoneIdentifier: TimeZone.current.identifier,
                discarding: ownCode
            )
            // The request is recorded on the account too; the account listener
            // (AccountSessionView) moves every device to "waiting for approval".
        } catch {
            // The pairing filled up, was cancelled, or someone else asked,
            // between the check and now.
            errorMessage = "Couldn't send the request. Check the code with your partner and try again."
        }
        isWorking = false
    }
}
