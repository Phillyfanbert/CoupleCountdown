// SettingsView.swift — per-couple theme selection and app settings (DESIGN.md §9)

import SwiftUI

struct SettingsView: View {
    @AppStorage("selectedTheme") private var selectedTheme: String = CoupleTheme.classic.rawValue

    var body: some View {
        Form {
            Picker("Theme", selection: $selectedTheme) {
                ForEach(CoupleTheme.allCases, id: \.rawValue) { theme in
                    Text(theme.displayName).tag(theme.rawValue)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

/// Placeholder theme set — DESIGN.md §9 leaves the actual gradient/color
/// design as craft-time work, not architectural; real values TBD, and
/// each needs its contrast checked in both light and dark appearance
/// before shipping (§9).
enum CoupleTheme: String, CaseIterable {
    case classic
    case sunset
    case midnight

    var displayName: String {
        switch self {
        case .classic: "Classic"
        case .sunset: "Sunset"
        case .midnight: "Midnight"
        }
    }
}
