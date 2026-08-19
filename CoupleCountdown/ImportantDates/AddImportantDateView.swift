// AddImportantDateView.swift — form for adding a new anniversary/important date (DESIGN.md §7.4)

import SwiftUI
import CoupleCountdownKit

struct AddImportantDateView: View {
    let coupleId: String
    let onSaved: () -> Void

    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var date = Date()
    @State private var repeatsAnnually = true
    @State private var isSaving = false
    @State private var errorMessage: String?

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
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("Add Important Date")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .accessibilityIdentifier("saveImportantDateButton")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() async {
        guard let uid = authService.uid else { return }
        isSaving = true
        errorMessage = nil
        // Deliberately separate from RelationshipState/nextMeetupDate —
        // informational countdowns, not tied to the apart/together state
        // machine (§7.4).
        let newDate = ImportantDate(
            id: UUID().uuidString,
            label: label,
            date: date,
            repeatsAnnually: repeatsAnnually,
            createdBy: uid
        )
        do {
            try await firestore.addImportantDate(newDate, coupleId: coupleId)
            // Only report success and dismiss if the write actually
            // succeeded — previously this ran unconditionally, so a
            // failed save looked identical to a successful one.
            onSaved()
            dismiss()
        } catch {
            errorMessage = "Couldn't save — check your connection and try again."
        }
        isSaving = false
    }
}
