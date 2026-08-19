// ImportantDatesListView.swift — list of anniversary/important-date counters (DESIGN.md §7.4)

import SwiftUI
import CoupleCountdownKit

struct ImportantDatesListView: View {
    let coupleId: String
    @State private var dates: [ImportantDate] = []
    @State private var errorMessage: String?
    @State private var isShowingAddSheet = false

    @AppStorage("selectedTheme", store: UserDefaults(suiteName: SharedIdentifiers.appGroup))
    private var selectedThemeRaw: String = CoupleTheme.blush.rawValue
    private var theme: CoupleTheme { CoupleTheme(rawValue: selectedThemeRaw) ?? .blush }

    private let firestore = FirestoreService()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }
            if dates.isEmpty && errorMessage == nil {
                ContentUnavailableView(
                    "No important dates yet",
                    systemImage: "calendar.badge.plus",
                    description: Text("Add your anniversary or another date worth counting down to.")
                )
            }
            ForEach(dates) { date in
                HStack {
                    Image(systemName: date.repeatsAnnually ? "gift.fill" : "star.fill")
                        .foregroundStyle(theme.accentColor)
                    VStack(alignment: .leading) {
                        Text(date.label).font(.system(.headline, design: .rounded))
                        Text(date.nextOccurrence(), format: .dateTime.year().month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackground()
        .navigationTitle("📅 Important Dates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { isShowingAddSheet = true }
                    .tint(theme.accentColor)
            }
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddImportantDateView(coupleId: coupleId) {
                Task { await load() }
            }
        }
        .refreshable {
            await load()
        }
        .task {
            await load()
        }
    }

    private func load() async {
        do {
            dates = try await firestore.fetchImportantDates(coupleId: coupleId)
            errorMessage = nil
        } catch {
            // Previously silently showed an empty list on failure,
            // indistinguishable from "no dates added yet."
            errorMessage = "Couldn't load — pull to refresh or try again."
        }
    }
}
