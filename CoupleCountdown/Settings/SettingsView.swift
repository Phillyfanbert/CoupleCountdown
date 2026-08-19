// SettingsView.swift — per-couple theme selection and app settings (DESIGN.md §9)

import SwiftUI
import CoupleCountdownKit

struct SettingsView: View {
    // Same shared App Group store as ThemedBackground reads from — was
    // previously the default local store, meaning a theme choice here
    // would never actually have been reflected anywhere it's displayed.
    @AppStorage("selectedTheme", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var selectedTheme: String = CoupleTheme.blush.rawValue

    var body: some View {
        Form {
            Section("Theme") {
                ForEach(CoupleTheme.allCases) { theme in
                    Button {
                        selectedTheme = theme.rawValue
                    } label: {
                        HStack {
                            Circle()
                                .fill(theme.accentColor)
                                .frame(width: 24, height: 24)
                            Text("\(theme.emoji) \(theme.displayName)")
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedTheme == theme.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(theme.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}
