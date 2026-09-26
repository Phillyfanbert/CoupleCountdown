// SignInView.swift — create an account or sign in (email + password)

import SwiftUI
import CoupleCountdownKit

/// One account works on every device — the iPhone app and the web client —
/// and they all show the same pairing.
struct SignInView: View {
    @EnvironmentObject private var authService: AuthService

    private enum Mode { case createAccount, signIn }
    private enum Field { case name, email, password }

    @State private var mode: Mode = .createAccount
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var noteMessage: String?
    @State private var isWorking = false
    @FocusState private var focusedField: Field?

    private let firestore = FirestoreService()

    /// This iPhone still holds a pairing from before accounts existed (an
    /// anonymous identity that's a participant in it).
    private var hasLegacyPairing: Bool {
        authService.hasLegacyAnonymousSession &&
            UserDefaults(suiteName: SharedIdentifiers.appGroup)?.string(forKey: "coupleId")?.isEmpty == false
    }

    private var introText: String {
        switch (mode, hasLegacyPairing) {
        case (.createAccount, true):
            return "Create an account to keep the pairing on this iPhone — then sign in with it on your computer too."
        case (.signIn, true):
            // Signing in replaces the old identity, and a pairing's members
            // can't be changed afterwards — so that pairing would be lost.
            return "This iPhone has a pairing from before accounts. Signing in to an existing account leaves it behind for good — create an account instead to keep it."
        default:
            return "Use the same account in this app and on the web — you'll see the same countdown on your phone and your computer."
        }
    }

    private var canSubmit: Bool {
        !isWorking && !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty &&
            (mode == .signIn || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("💕")
                    .font(.system(size: 56))
                    .padding(.top, 40)

                Text(mode == .createAccount ? "Create your account" : "Welcome back")
                    .font(.system(.title2, design: .rounded, weight: .semibold))

                Text(introText)
                    .font(.footnote)
                    .foregroundStyle(hasLegacyPairing && mode == .signIn ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("authIntroText")

                VStack(spacing: 12) {
                    if mode == .createAccount {
                        TextField("Your name (what your partner sees)", text: $name)
                            .textContentType(.givenName)
                            .onChange(of: name) { _, newName in
                                if newName.count > PartnerProfile.maxNameLength {
                                    name = String(newName.prefix(PartnerProfile.maxNameLength))
                                }
                            }
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .email }
                            .accessibilityIdentifier("authNameField")
                    }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .accessibilityIdentifier("authEmailField")
                    SecureField(mode == .createAccount ? "Password (6+ characters)" : "Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit {
                            if canSubmit { Task { await submit() } }
                        }
                        .accessibilityIdentifier("authPasswordField")
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .rounded))
                .padding(.horizontal, 24)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("authErrorText")
                }
                if let noteMessage {
                    Text(noteMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .accessibilityIdentifier("authNoteText")
                }

                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text(mode == .createAccount ? "Create account" : "Sign in")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .disabled(!canSubmit)
                .accessibilityIdentifier("authSubmitButton")

                Button(mode == .createAccount ? "Already have an account? Sign in" : "New here? Create an account") {
                    mode = mode == .createAccount ? .signIn : .createAccount
                    errorMessage = nil
                    noteMessage = nil
                }
                .font(.footnote.weight(.semibold))
                .accessibilityIdentifier("authToggleButton")

                if mode == .signIn {
                    Button("Forgot password?") {
                        Task { await resetPassword() }
                    }
                    .font(.footnote)
                    .accessibilityIdentifier("forgotPasswordButton")
                }
            }
            .padding()
        }
        .themedBackground()
        .tint(CoupleTheme.blush.accentColor)
    }

    private func submit() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Put the keyboard away now, while the request runs. Left up, it was
        // still covering the lower half of the next screen (onboarding's
        // Create/Join buttons) when that screen appeared — caught by the UI
        // tests, whose taps landed on nothing.
        focusedField = nil
        isWorking = true
        errorMessage = nil
        noteMessage = nil
        do {
            switch mode {
            case .signIn:
                try await authService.signIn(email: trimmedEmail, password: password)
            case .createAccount:
                try await authService.createAccount(email: trimmedEmail, password: password) { uid, upgradedAnonymous in
                    // A pairing made on this iPhone before accounts existed
                    // belongs to the identity that was just upgraded (same
                    // uid), so it moves onto the account.
                    let legacyCoupleId = upgradedAnonymous
                        ? UserDefaults(suiteName: SharedIdentifiers.appGroup)?.string(forKey: "coupleId")
                        : nil
                    try await firestore.saveProfile(
                        uid: uid,
                        displayName: trimmedName,
                        coupleId: (legacyCoupleId?.isEmpty == false) ? legacyCoupleId : nil
                    )
                }
            }
        } catch {
            errorMessage = AuthService.message(for: error)
        }
        isWorking = false
    }

    private func resetPassword() async {
        focusedField = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        noteMessage = nil
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Enter your email above first."
            return
        }
        do {
            try await authService.sendPasswordReset(email: trimmedEmail)
            // Same wording whether or not the account exists, so this can't be
            // used to check which emails have accounts.
            noteMessage = "If there's an account for that email, a reset link is on its way."
        } catch {
            errorMessage = AuthService.message(for: error)
        }
    }
}
