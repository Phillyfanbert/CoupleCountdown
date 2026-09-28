// AddImportantDateView.swift: form for adding a new anniversary/important date (DESIGN.md §7.4)

import SwiftUI
import CoupleCountdownKit

struct AddImportantDateView: View {
    let coupleId: String
    let onSaved: () -> Void
    /// The server rejected the save, after the sheet had closed.
    let onFailed: () -> Void

    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var date = Date()
    @State private var repeatsAnnually = true

    private let firestore = FirestoreService()

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label (e.g. Anniversary)", text: $label)
                    .accessibilityIdentifier("dateLabelTextField")
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .accessibilityIdentifier("importantDatePicker")
                Toggle("Repeats every year", isOn: $repeatsAnnually)
                    .accessibilityIdentifier("repeatsAnnuallyToggle")
            }
            .navigationTitle("Add Important Date")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("saveImportantDateButton")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let uid = authService.uid else { return }
        // Deliberately separate from RelationshipState/nextMeetupDate:
        // informational countdowns, not tied to the apart/together state
        // machine (§7.4).
        let newDate = ImportantDate(
            id: UUID().uuidString,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            // The picked *day*, stored so it reads as the same day for a
            // partner in another time zone (see CalendarDay). Storing the
            // picker's instant showed it a day early to anyone further west.
            date: CalendarDay(localDate: date).storedDate,
            repeatsAnnually: repeatsAnnually,
            createdBy: uid
        )
        // Saved on this device at once and synced when the connection allows
        // (offline it used to spin until reconnecting). A save the server
        // rejects is still reported, on the calendar underneath, so a
        // failure never passes for a success.
        firestore.addImportantDate(newDate, coupleId: coupleId, onFailure: { _ in
            Task { @MainActor in onFailed() }
        })
        onSaved()
        dismiss()
    }
}
