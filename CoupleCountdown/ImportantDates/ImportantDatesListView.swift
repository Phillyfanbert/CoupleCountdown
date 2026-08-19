// ImportantDatesListView.swift — list of anniversary/important-date counters (DESIGN.md §7.4)

import SwiftUI
import CoupleCountdownKit

struct ImportantDatesListView: View {
    let coupleId: String
    @State private var dates: [ImportantDate] = []
    @State private var errorMessage: String?
    @State private var isShowingAddSheet = false

    private let firestore = FirestoreService()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }
            ForEach(dates) { date in
                VStack(alignment: .leading) {
                    Text(date.label).font(.headline)
                    Text(date.nextOccurrence(), format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Important Dates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { isShowingAddSheet = true }
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
