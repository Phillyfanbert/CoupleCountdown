// VisitPlannerSheet.swift: pick a date *and time* for a visit

import SwiftUI
import CoupleCountdownKit

/// Used when leaving ("when do you see each other next?"), when planning or
/// changing the next visit from the countdown, and from the calendar.
///
/// Takes a real meeting time: the countdown ends when the flight lands, not
/// at some arbitrary hour. The old date-only picker left the countdown ending
/// at whatever time of day the screen happened to be built, and it accepted
/// dates in the past.
struct VisitPlannerSheet: View {
    let title: String
    /// The other partner, when they're in a different time zone: the time can
    /// then be entered as theirs. It used to be read silently in this
    /// phone's zone, so a traveler entering the landing time at the other end
    /// ended the countdown hours early or late.
    let partner: PartnerProfile?
    let errorMessage: String?
    let onSave: (_ start: Date, _ note: String?) async -> Void
    let onCancel: () -> Void

    @State private var start: Date
    @State private var note = ""
    @State private var isSaving = false
    @State private var inPartnersTime = false

    @AppStorage("selectedTheme", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var selectedThemeRaw: String = CoupleTheme.blush.rawValue
    private var theme: CoupleTheme { CoupleTheme(rawValue: selectedThemeRaw) ?? .blush }

    init(
        title: String,
        initialStart: Date? = nil,
        partner: PartnerProfile? = nil,
        errorMessage: String?,
        onSave: @escaping (_ start: Date, _ note: String?) async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.errorMessage = errorMessage
        // Only worth offering when their zone differs from this phone's.
        self.partner = partner.flatMap {
            $0.timeZoneIdentifier == TimeZone.autoupdatingCurrent.identifier ? nil : $0
        }
        self.onSave = onSave
        self.onCancel = onCancel
        _start = State(initialValue: initialStart ?? (Self.isQuickVisitTest ? Self.quickTestStart() : Self.defaultStart()))
    }

    /// UI tests only: a visit starting within about a minute, so a test can
    /// watch a real countdown run out. (The start is kept on a whole minute,
    /// since saved visits are trimmed to the minute.)
    private static let isQuickVisitTest = ProcessInfo.processInfo.arguments.contains("-uiTestQuickVisit")

    static func quickTestStart(now: Date = Date()) -> Date {
        Date(timeIntervalSince1970: ((now.timeIntervalSince1970 + 20) / 60).rounded(.up) * 60)
    }

    /// A week from today at 6 PM, computed each time the sheet opens, not
    /// once when the screen behind it was built (that default went stale).
    static func defaultStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let weekAhead = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: weekAhead) ?? weekAhead
    }

    private var partnerZone: TimeZone {
        partner.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .autoupdatingCurrent
    }

    private static func when(in zone: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: zone)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let partner {
                    Picker("Whose time?", selection: $inPartnersTime) {
                        Text("Mine").tag(false)
                        Text("\(partner.displayName)'s").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("visitZonePicker")
                    // Switching keeps the time as typed: 6:30 PM becomes 6:30 PM theirs.
                    .onChange(of: inPartnersTime) { wasPartners, isPartners in
                        start = MeetupPlanner.sameWallTime(
                            start,
                            from: wasPartners ? partnerZone : .autoupdatingCurrent,
                            to: isPartners ? partnerZone : .autoupdatingCurrent
                        )
                    }
                }
                DatePicker("When", selection: $start, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .environment(\.timeZone, inPartnersTime ? partnerZone : .autoupdatingCurrent)
                    .accessibilityIdentifier("nextMeetupDatePicker")
                if let partner {
                    // The same moment for both of them, so a mix-up shows before saving.
                    Text("For you: \(start.formatted(Self.when(in: .autoupdatingCurrent)))\nFor \(partner.displayName): \(start.formatted(Self.when(in: partnerZone)))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("visitZoneSummary")
                }
                TextField("Note (optional), e.g. Sam lands at LAX", text: $note)
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
