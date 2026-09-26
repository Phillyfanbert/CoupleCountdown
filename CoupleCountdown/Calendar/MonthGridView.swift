// MonthGridView.swift: a month of days with markers for visits and important dates

import SwiftUI

struct MonthGridView: View {
    /// Local midnight of the first day of the month shown.
    let month: Date
    /// Local midnight of each day that has a planned visit / an important date.
    let visitDays: Set<Date>
    let importantDays: Set<Date>
    @Binding var selectedDay: Date?
    let accent: Color
    let onChangeMonth: (_ delta: Int) -> Void

    private let calendar = Calendar.current

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// nil for the blank cells before the 1st.
    private var cells: [Date?] {
        guard let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let dates = days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: leading) + dates
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { onChangeMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                    .accessibilityIdentifier("previousMonthButton")
                Spacer()
                Text(month, format: .dateTime.month(.wide).year())
                    .font(.system(.headline, design: .rounded))
                    .accessibilityIdentifier("calendarMonthTitle")
                Spacer()
                Button { onChangeMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
                    .accessibilityIdentifier("nextMonthButton")
            }
            .buttonStyle(.borderless)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay == day
        let hasVisit = visitDays.contains(day)
        let hasDate = importantDays.contains(day)
        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(.callout, design: .rounded, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(width: 30, height: 30)
                    .background {
                        if isSelected {
                            Circle().fill(accent)
                        } else if isToday {
                            Circle().stroke(accent, lineWidth: 1.5)
                        }
                    }
                HStack(spacing: 3) {
                    if hasVisit { Circle().fill(accent).frame(width: 5, height: 5) }
                    if hasDate { Circle().fill(Color.secondary).frame(width: 5, height: 5) }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText(day, isToday: isToday, hasVisit: hasVisit, hasDate: hasDate))
        // Local time zone: the default ISO style is UTC, which labels a
        // local-midnight day as the previous day east of UTC.
        .accessibilityIdentifier("calendarDay_\(day.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()))")
    }

    private func accessibilityText(_ day: Date, isToday: Bool, hasVisit: Bool, hasDate: Bool) -> String {
        var parts = [day.formatted(.dateTime.month(.wide).day())]
        if isToday { parts.append("today") }
        if hasVisit { parts.append("visit planned") }
        if hasDate { parts.append("important date") }
        return parts.joined(separator: ", ")
    }
}
