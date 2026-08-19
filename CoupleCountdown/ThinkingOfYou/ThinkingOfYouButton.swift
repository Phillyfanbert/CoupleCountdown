// ThinkingOfYouButton.swift — one-tap "thinking of you" nudge (DESIGN.md §7.1)

import SwiftUI
import CoupleCountdownKit

struct ThinkingOfYouButton: View {
    let coupleId: String

    @EnvironmentObject private var authService: AuthService
    @State private var isSending = false
    @State private var didSend = false
    @State private var didFail = false

    @AppStorage("selectedTheme", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var selectedThemeRaw: String = CoupleTheme.blush.rawValue
    private var theme: CoupleTheme { CoupleTheme(rawValue: selectedThemeRaw) ?? .blush }

    private let firestore = FirestoreService()

    var body: some View {
        VStack(spacing: 4) {
            Button {
                Task { await send() }
            } label: {
                Label(didSend ? "Sent, with love" : "Send a little \"thinking of you\"", systemImage: didSend ? "heart.fill" : "paperplane.fill")
                    .symbolEffect(.bounce, value: didSend)
            }
            .buttonStyle(.bordered)
            .tint(theme.accentColor)
            .disabled(isSending || authService.uid == nil)

            if didFail {
                Text("Couldn't send — try again").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func send() async {
        guard let uid = authService.uid else { return }
        isSending = true
        didFail = false
        do {
            // Not an instant push (DESIGN.md §2, §5.4) — this only
            // surfaces to the partner next time their app or widget
            // refreshes.
            try await firestore.sendPing(coupleId: coupleId, uid: uid)
            // Only show "Sent" if the write actually succeeded —
            // previously this fired unconditionally, so a failed send
            // looked identical to a successful one.
            didSend = true
        } catch {
            didFail = true
        }
        isSending = false
        if didSend {
            try? await Task.sleep(for: .seconds(2))
            didSend = false
        }
    }
}
