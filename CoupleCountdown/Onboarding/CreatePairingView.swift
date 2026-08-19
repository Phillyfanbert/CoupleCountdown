// CreatePairingView.swift — generates and displays the join code + QR (DESIGN.md §5.3 point 3)

import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
import CoupleCountdownKit

struct CreatePairingView: View {
    let displayName: String
    @Binding var coupleId: String

    @EnvironmentObject private var authService: AuthService
    @State private var generatedCode: String?
    @State private var errorMessage: String?
    @State private var isCreating = false

    private let firestore = FirestoreService()

    var body: some View {
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

                if let qrImage = Self.qrCode(for: "couplecountdown://join/\(generatedCode)") {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 200, height: 200)
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: CoupleTheme.blush.accentColor.opacity(0.2), radius: 8, y: 4)
                }

                ShareLink(item: generatedCode) {
                    Label("Share code", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(CoupleTheme.blush.accentColor)

                // Manually reading/typing the code is the primary,
                // required path — QR/deep link is best-effort convenience
                // only (DESIGN.md §5.3).
                Text("Typing the code is the reliable way to pair — the QR code and share link are best-effort convenience.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Setting `coupleId` is what advances past onboarding —
                // it's bound all the way up to CoupleCountdownApp's
                // @AppStorage, so the instant it's set the whole app's
                // root view swaps to CountdownView. createPairing() used
                // to set it in the same breath as generatedCode, which
                // left ~0 real time to read/copy/share the code before it
                // vanished (caught by XCUITest: the code screen was
                // already gone by the time a test checked for it, only
                // seconds after the write completed). Requiring this tap
                // is what actually gives the code screen a real, user-
                // controlled lifetime.
                Button {
                    coupleId = generatedCode
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
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .padding()
        .themedBackground()
        .task {
            await createPairing()
        }
    }

    private func createPairing() async {
        guard let uid = authService.uid else {
            errorMessage = "Not signed in yet — try again in a moment."
            return
        }
        isCreating = true
        let code = JoinCodeGenerator.generate()
        do {
            try await firestore.createCouple(
                coupleId: code,
                uid: uid,
                displayName: displayName,
                timeZoneIdentifier: TimeZone.current.identifier
            )
            // Deliberately not also setting coupleId here — see the
            // Continue button below.
            generatedCode = code
        } catch {
            errorMessage = error.localizedDescription
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
