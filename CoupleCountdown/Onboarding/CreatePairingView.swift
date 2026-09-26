// CreatePairingView.swift: generates and displays the join code + QR (DESIGN.md §5.3 point 3)

import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
import CoupleCountdownKit

struct CreatePairingView: View {
    let displayName: String
    /// See AccountSessionView: keeps this screen (and its code) up after the
    /// account records the new pairing, until the user taps Continue.
    @Binding var holdingNewCode: Bool

    @EnvironmentObject private var authService: AuthService
    @State private var generatedCode: String?
    @State private var errorMessage: String?
    @State private var isCreating = false

    private let firestore = FirestoreService()

    var body: some View {
        // Scrollable: code + QR + share + note + Continue is taller than a
        // small iPhone (or any iPhone with the keyboard still up), which left
        // Continue off-screen and untappable.
        ScrollView {
            VStack(spacing: 20) {
                if let generatedCode {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundStyle(CoupleTheme.blush.accentColor)

                    Text("Your code")
                        .font(.system(.headline, design: .rounded))
                    Text(generatedCode)
                        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                        .textSelection(.enabled)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(CoupleTheme.blush.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityIdentifier("generatedCodeText")

                    if let qrImage = Self.qrCode(for: JoinLink.url(for: generatedCode).absoluteString) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 200, height: 200)
                            .padding(12)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: CoupleTheme.blush.accentColor.opacity(0.2), radius: 8, y: 4)
                    }

                    ShareLink(item: JoinLink.url(for: generatedCode), message: Text("Join me on CoupleCountdown with code \(generatedCode)")) {
                        Label("Share invite", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CoupleTheme.blush.accentColor)

                    // The QR code and invite link open the web app with the
                    // code filled in; typing the code works everywhere too.
                    Text("Your partner can scan this or open the invite to join on the web, or type the code in the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    // The account records the pairing as soon as it's created
                    // (so the user's other devices pick it up), but this screen
                    // only gives way to the countdown when the user taps
                    // Continue: advancing automatically once left ~0 real time
                    // to read/copy/share the code before it vanished (caught by
                    // XCUITest). The countdown's "waiting for your partner" card
                    // shows the code again afterwards.
                    Button {
                        holdingNewCode = false
                    } label: {
                        Label("Continue", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(CoupleTheme.blush.accentColor)
                    .accessibilityIdentifier("continueToCountdownButton")
                } else if isCreating {
                    ProgressView("Creating…")
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        self.errorMessage = nil
                        Task { await createPairing() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("retryCreatePairingButton")
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .themedBackground()
        .task {
            await createPairing()
        }
    }

    private func createPairing() async {
        guard let uid = authService.uid else {
            errorMessage = "Not signed in yet. Try again in a moment."
            return
        }
        isCreating = true
        // Must be set before the write: the account's listener sees the new
        // pairing as soon as the server confirms it.
        holdingNewCode = true
        let code = JoinCodeGenerator.generate()
        do {
            try await firestore.createCouple(
                coupleId: code,
                uid: uid,
                displayName: displayName,
                timeZoneIdentifier: TimeZone.current.identifier
            )
            generatedCode = code
        } catch {
            holdingNewCode = false
            errorMessage = "Couldn't create the pairing. Check your connection and try again."
        }
        isCreating = false
    }

    private static func qrCode(for string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
