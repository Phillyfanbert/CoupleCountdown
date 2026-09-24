// VisitPlannerSheet.swift — pick a date *and time* for a visit

import SwiftUI
import CoupleCountdownKit

/// Used when leaving ("when do you see each other next?"), when planning or
/// changing the next visit from the countdown, and from the calendar.
///
/// Takes a real meeting time — the countdown ends when the flight lands, not
/// at some arbitrary hour. The old date-only picker left the countdown ending
/// at whatever time of day the screen happened to be built, and it accepted
/// dates in the past.
struct VisitPlannerSheet: View {
    let title: String
    let errorMessage: String?
    let onSave: (_ start: Date, _ note: String?) async -> Void
    let onCancel: () -> Void

    @State private var start: Date
    @State private var note = ""
    @State private var isSaving = false

    @AppStorage("selectedTheme", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var selectedThemeRaw: String = CoupleTheme.blush.rawValue
    private var theme: CoupleTheme { CoupleTheme(rawValue: selectedThemeRaw) ?? .blush }

    init(
        title: String,
        initialStart: Date? = nil,
        errorMessage: String?,
        onSave: @escaping (_ start: Date, _ note: String?) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.errorMessage = errorMessage
        self.onSave = onSave
        self.onCancel = onCancel
        _start = State(initialValue: initialStart ?? Self.defaultStart())
    }

    /// A week from today at 6 PM — computed each time the sheet opens, not
    /// once when the screen behind it was built (that default went stale).
    static func defaultStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let weekAhead = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: weekAhead) ?? weekAhead
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("When", selection: $start, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("nextMeetupDatePicker")
                TextField("Note (optional) — e.g. Sam lands at LAX", text: $note)
                    .accessibilityIdentifier("visitNoteField")
                // Shown inside the sheet: a save failure shown only on the
                // screen underneath would be invisible while this is up.
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            await onSave(start, note)
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                    .tint(theme.accentColor)
                    .accessibilityIdentifier("saveDateButton")
                }
            }
        }
    }
}
