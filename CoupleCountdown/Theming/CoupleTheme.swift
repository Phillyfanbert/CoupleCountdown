// CoupleTheme.swift — per-couple visual theme: background gradient + accent color (DESIGN.md §9)

import SwiftUI
import CoupleCountdownKit

/// Real values for the theme placeholder DESIGN.md §9 originally left as
/// craft-time work. Each theme defines separate light/dark gradients
/// (§9's own note: theme colors need contrast checked in both
/// appearances, not just designed against one) plus a single accent
/// color used for buttons, hearts, and other warm touches — chosen to
/// read clearly against both variants rather than needing its own
/// light/dark split.
enum CoupleTheme: String, CaseIterable, Identifiable {
    case blush
    case sunset
    case midnight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blush: "Blush"
        case .sunset: "Sunset"
        case .midnight: "Midnight"
        }
    }

    /// A little personality for the theme picker — no functional role.
    var emoji: String {
        switch self {
        case .blush: "💗"
        case .sunset: "🌅"
        case .midnight: "🌙"
        }
    }

    var accentColor: Color {
        switch self {
        case .blush: Color(hex: "FF6F91")
        case .sunset: Color(hex: "FF7B54")
        case .midnight: Color(hex: "C77DFF")
        }
    }

    func backgroundGradient(for colorScheme: ColorScheme) -> LinearGradient {
        let colors: [Color]
        switch (self, colorScheme) {
        case (.blush, .dark):
            colors = [Color(hex: "3A1F2B"), Color(hex: "2B1A33")]
        case (.blush, _):
            colors = [Color(hex: "FFD9E8"), Color(hex: "FFF3E0")]

        case (.sunset, .dark):
            colors = [Color(hex: "3D1F2B"), Color(hex: "4A2E1F")]
        case (.sunset, _):
            colors = [Color(hex: "FFB199"), Color(hex: "FFE29A")]

        case (.midnight, .dark):
            colors = [Color(hex: "1A1B3A"), Color(hex: "2D1B4E")]
        case (.midnight, _):
            colors = [Color(hex: "D4C1EC"), Color(hex: "C1D9F0")]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Reads the shared @AppStorage-backed theme selection so any screen can
/// apply it — same store as CoupleCountdownApp uses for `coupleId`, so
/// the theme choice (like pairing) is shared across the app and widget
/// rather than being per-device.
struct ThemedBackground: ViewModifier {
    @AppStorage("selectedTheme", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var selectedTheme: String = CoupleTheme.blush.rawValue
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                (CoupleTheme(rawValue: selectedTheme) ?? .blush)
                    .backgroundGradient(for: colorScheme)
                    .ignoresSafeArea()
            )
    }
}

extension View {
    /// Applies the couple's chosen background gradient behind this view.
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }
}
