// OnboardingView.swift — Create/Join entry screen for a signed-in account without a pairing (DESIGN.md §5.3 point 2)

import SwiftUI

struct OnboardingView: View {
    let uid: String
    /// The account's display name — set at sign-up, so the name step only
    /// appears for an account that somehow has none.
    let profileName: String?
    @Binding var holdingNewCode: Bool

    @EnvironmentObject private var authService: AuthService
    @State private var nameDraft = ""
    @State private var nameError: String?
    @State private var path: Path = .choice

    private enum Path {
        case choice
        case create
        case join
    }

    private let firestore = FirestoreService()

    private var displayName: String? {
        guard let profileName, !profileName.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return profileName
    }

    var body: some View {
        NavigationStack {
            Group {
                if let displayName {
                    switch path {
                    case .choice:
                        choiceView(displayName: displayName)
                    case .create:
                        CreatePairingView(displayName: displayName, holdingNewCode: $holdingNewCode)
                    case .join:
                        JoinPairingView(displayName: displayName) { path = .choice }
                    }
                } else {
                    VStack {
                        DisplayNameEntryView(displayName: $nameDraft) {
                            Task { await saveName() }
                        }
                        if let nameError {
                            Text(nameError).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
            .themedBackground()
            .navigationTitle("💕 CoupleCountdown")
        }
        .tint(CoupleTheme.blush.accentColor)
    }

    private func saveName() async {
        nameError = nil
        do {
            // The account record's listener (AccountSessionView) picks the
            // new name up and re-renders this view past the name step.
            try await firestore.saveProfile(uid: uid, displayName: nameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            nameError = "Couldn't save — check your connection and try again."
        }
    }

    private func choiceView(displayName: String) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(CoupleTheme.blush.accentColor)

                Text("Hi \(displayName) — let's get you two set up")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)

                // Heads off the obvious failure mode (DESIGN.md §5.3 point 2).
                // If both partners do tap Create anyway, either can cancel theirs
                // from the countdown screen's "waiting for your partner" card.
                Text("Only one of you should tap Create — have your partner tap Join with the code you'll get next. Already paired? Sign in with that account instead.")
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
                    .accessibilityIdentifier("createPairingButton")

                    Button {
                        path = .join
                    } label: {
                        Label("Join a Pairing", systemImage: "envelope.open.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("joinPairingButton")
                }
                .padding(.horizontal, 32)

                VStack(spacing: 4) {
                    if let email = authService.email {
                        Text("Signed in as \(email)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Sign out") { authService.signOut() }
                        .font(.footnote)
                        .accessibilityIdentifier("onboardingSignOutButton")
                }
            }
            .padding()
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
        }
    }
}
