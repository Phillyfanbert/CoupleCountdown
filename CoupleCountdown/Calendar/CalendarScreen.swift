// CalendarScreen.swift — planned visits and important dates, on a month grid and as a countdown list

import SwiftUI
import CoupleCountdownKit

/// Replaces the old Important Dates list, which could only hold one kind of
/// thing, listed it in random (document-ID) order, and showed no countdown.
/// Here a couple can plan several visits (each with a time) and keep their
/// anniversaries, see both on a month grid, and see how many days away each
/// one is. The main countdown follows the next planned visit.
struct CalendarScreen: View {
    let coupleId: String
    /// Hands the updated couple state back to the countdown screen's sync,
    /// so its countdown and the widget update at once when a visit changes
    /// the next meetup (§5.2's sync pipeline convention).
    let onCoupleStateChanged: (RelationshipState) -> Void

    @EnvironmentObject private var authService: AuthService

    @State private var visits: [Visit] = []
    @State private var dates: [ImportantDate] = []
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var selectedDay: Date?
    @State private var isShowingAddDate = false
    @State private var isShowingPlanVisit = false
    @State private var visitError: String?

    @AppStorage("selectedTheme", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var selectedThemeRaw: String = CoupleTheme.blush.rawValue
    private var theme: CoupleTheme { CoupleTheme(rawValue: selectedThemeRaw) ?? .blush }

    private let firestore = FirestoreService()
    private let calendar = Calendar.current

    // MARK: - Agenda

    private enum Item: Identifiable {
        case visit(Visit)
        case date(ImportantDate, on: Date)

        var id: String {
            switch self {
            case .visit(let visit): return "visit-\(visit.id)"
            case .date(let date, _): return "date-\(date.id)"
            }
        }

        var when: Date {
            switch self {
            case .visit(let visit): return visit.start
            case .date(_, let on): return on
            }
        }
    }

    private var upcoming: [Item] {
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let visitItems = visits.filter { $0.start > now }.map(Item.visit)
        let dateItems = dates
            .map { ($0, $0.nextOccurrence(now: now)) }
            .filter { $0.1 >= startOfToday }
            .map { Item.date($0.0, on: $0.1) }
        return (visitItems + dateItems).sorted { $0.when < $1.when }
    }

    /// Past visits and past one-off dates, most recent first — kept out of
    /// the way below what's coming up.
    private var past: [Item] {
        let now = Date()
        let visitItems = visits.filter { $0.start <= now }.map(Item.visit)
        let dateItems = dates.filter { $0.isPast(now: now) }.map { Item.date($0, on: $0.nextOccurrence(now: now)) }
        return Array((visitItems + dateItems).sorted { $0.when > $1.when }.prefix(10))
    }

    // MARK: - Month grid data

    private var visitDays: Set<Date> {
        Set(visits.map { calendar.startOfDay(for: $0.start) })
    }

    /// Important dates on the displayed month — yearly ones on their day in
    /// that month's year, one-off ones only in their own year.
    private var importantDays: Set<Date> {
        let year = calendar.component(.year, from: displayedMonth)
        return Set(dates.compactMap { occurrence(of: $0, inYear: year) })
    }

    private func occurrence(of date: ImportantDate, inYear year: Int) -> Date? {
        let day = date.day
        if !date.repeatsAnnually && day.year != year { return nil }
        return calendar.date(from: DateComponents(year: year, month: day.month, day: day.day))
    }

    private func items(on day: Date) -> [Item] {
        let year = calendar.component(.year, from: day)
        let visitItems = visits.filter { calendar.isDate($0.start, inSameDayAs: day) }.map(Item.visit)
        let dateItems = dates.filter { occurrence(of: $0, inYear: year) == day }.map { Item.date($0, on: day) }
        return (visitItems + dateItems).sorted { $0.when < $1.when }
    }

    // MARK: - Body

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }

            Section {
                MonthGridView(
                    month: displayedMonth,
                    visitDays: visitDays,
                    importantDays: importantDays,
                    selectedDay: $selectedDay,
                    accent: theme.accentColor,
                    onChangeMonth: { delta in
                        if let month = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
                            displayedMonth = month
                        }
                    }
                )
                .padding(.vertical, 4)
            }

            if let selectedDay {
                Section(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                    let dayItems = items(on: selectedDay)
                    if dayItems.isEmpty {
                        Text("Nothing planned").foregroundStyle(.secondary)
                    }
                    ForEach(dayItems) { itemRow($0) }
                }
            }

            Section {
                HStack(spacing: 12) {
                    Button {
                        visitError = nil
                        isShowingPlanVisit = true
                    } label: {
                        Label("Plan a visit", systemImage: "airplane")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("planVisitFromCalendarButton")

                    Button {
                        isShowingAddDate = true
                    } label: {
                        Label("Add a date", systemImage: "gift")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("addImportantDateButton")
                }
                .listRowBackground(Color.clear)
            }

            Section("Coming up") {
                if hasLoaded && upcoming.isEmpty {
                    Text("Nothing yet — plan your next visit, or add your anniversary.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("nothingComingUpText")
                }
                ForEach(upcoming) { itemRow($0) }
            }

            if !past.isEmpty {
                Section("Past") {
                    ForEach(past) { itemRow($0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackground()
        .tint(theme.accentColor)
        .navigationTitle("📅 Calendar")
        .sheet(isPresented: $isShowingAddDate) {
            AddImportantDateView(coupleId: coupleId) {
                Task { await load() }
            }
        }
        .sheet(isPresented: $isShowingPlanVisit) {
            VisitPlannerSheet(
                title: "Plan a visit ✈️",
                initialStart: selectedDayStart,
                errorMessage: visitError,
                onSave: { start, note in await saveVisit(start: start, note: note) },
                onCancel: { isShowingPlanVisit = false }
            )
        }
        .refreshable { await load() }
        .task { await load() }
    }

    /// Planning a visit with a future day selected starts it on that day.
    private var selectedDayStart: Date? {
        guard let selectedDay, selectedDay >= calendar.startOfDay(for: Date()) else { return nil }
        let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: selectedDay)
        return start.flatMap { $0 > Date() ? $0 : nil }
    }

    @ViewBuilder
    private func itemRow(_ item: Item) -> some View {
        switch item {
        case .visit(let visit):
            HStack {
                Image(systemName: "airplane").foregroundStyle(theme.accentColor)
                VStack(alignment: .leading) {
                    Text(visit.note ?? "Visit").font(.system(.headline, design: .rounded))
                    Text(visit.start, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(CountdownFormatter.relativeDayLabel(CountdownFormatter.calendarDays(from: Date(), to: visit.start)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accentColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("visitRow")
            .swipeActions {
                Button(role: .destructive) {
                    Task { await deleteVisit(visit) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        case .date(let date, let on):
            HStack {
                Image(systemName: date.repeatsAnnually ? "gift.fill" : "star.fill")
                    .foregroundStyle(theme.accentColor)
                VStack(alignment: .leading) {
                    Text(date.label).font(.system(.headline, design: .rounded))
                    Text(on, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(CountdownFormatter.relativeDayLabel(CountdownFormatter.calendarDays(from: Date(), to: on)))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accentColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("importantDateRow_\(date.label)")
            .swipeActions {
                Button(role: .destructive) {
                    Task { await deleteDate(date) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Data

    private func load() async {
        do {
            async let fetchedVisits = firestore.fetchVisits(coupleId: coupleId)
            async let fetchedDates = firestore.fetchImportantDates(coupleId: coupleId)
            visits = try await fetchedVisits
            dates = try await fetchedDates
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load — pull to refresh or try again."
        }
        hasLoaded = true
    }

    private func saveVisit(start: Date, note: String?) async {
        guard let uid = authService.uid else { return }
        visitError = nil
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let visit = Visit(
            id: UUID().uuidString,
            start: MeetupPlanner.normalized(start),
            note: (trimmedNote?.isEmpty == false) ? trimmedNote : nil,
            createdBy: uid
        )
        do {
            try await firestore.addVisit(visit, coupleId: coupleId)
            visits.append(visit)
            try await followPlan(removed: nil)
            isShowingPlanVisit = false
        } catch {
            visitError = "Couldn't save the visit — check your connection and try again."
        }
    }

    private func deleteVisit(_ visit: Visit) async {
        do {
            try await firestore.deleteVisit(id: visit.id, coupleId: coupleId)
            visits.removeAll { $0.id == visit.id }
            try await followPlan(removed: visit)
        } catch {
            errorMessage = "Couldn't delete — check your connection and try again."
        }
    }

    private func deleteDate(_ date: ImportantDate) async {
        do {
            try await firestore.deleteImportantDate(id: date.id, coupleId: coupleId)
            dates.removeAll { $0.id == date.id }
        } catch {
            errorMessage = "Couldn't delete — check your connection and try again."
        }
    }

    /// Points the main countdown at the next planned visit when the plan changes.
    private func followPlan(removed: Visit?) async throws {
        guard let uid = authService.uid else { return }
        let current = try await firestore.fetchCouple(coupleId: coupleId)
        let resolved = MeetupPlanner.resolvedNextMeetup(current: current.nextMeetupDate, visits: visits, removed: removed)
        guard resolved != current.nextMeetupDate else { return }
        try await firestore.setNextMeetupDate(resolved, coupleId: coupleId, uid: uid)
        var updated = current
        updated.nextMeetupDate = resolved
        updated.lastUpdatedBy = uid
        updated.lastUpdatedAt = Date()
        onCoupleStateChanged(updated)
    }
}
