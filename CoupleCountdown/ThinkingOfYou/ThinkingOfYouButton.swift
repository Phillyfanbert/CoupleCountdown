// ThinkingOfYouButton.swift — one-tap "thinking of you" nudge (DESIGN.md §7.1)

import SwiftUI

struct ThinkingOfYouButton: View {
    let coupleId: String

    @EnvironmentObject private var authService: AuthService
    @State private var isSending = false
    @State private var didSend = false

    private let firestore = FirestoreService()

    var body: some View {
        Button {
            Task { await send() }
        } label: {
            Label(didSend ? "Sent" : "Thinking of you", systemImage: didSend ? "checkmark" : "heart")
        }
        .buttonStyle(.bordered)
        .disabled(isSending || authService.uid == nil)
    }

    private func send() async {
        guard let uid = authService.uid else { return }
        isSending = true
        // Not an instant push (DESIGN.md §2, §5.4) — this only surfaces
        // to the partner next time their app or widget refreshes.
        try? await firestore.sendPing(coupleId: coupleId, uid: uid)
        isSending = false
        didSend = true
        try? await Task.sleep(for: .seconds(2))
        didSend = false
    }
}
