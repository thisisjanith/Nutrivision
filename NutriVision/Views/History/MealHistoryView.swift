//
//  MealHistoryView.swift
//  NutriVision
//

import SwiftUI
import SwiftData
import Charts

struct MealHistoryView: View {
    enum RangeOption: String, CaseIterable, Identifiable {
        case week = "Week"
        case month = "Month"
        var id: String { rawValue }
    }

    private struct MacroSlice: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }

    @Query(sort: \MealEntry.timestamp, order: .reverse) private var allMeals: [MealEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var range: RangeOption = .week

    private var rangeStart: Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        switch range {
        case .week:
            return calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: startOfToday) ?? startOfToday
        }
    }

    private var filteredMeals: [MealEntry] {
        allMeals.filter { $0.timestamp >= rangeStart }
    }

    private var totals: DashboardViewModel.MacroTotals {
        filteredMeals.reduce(into: DashboardViewModel.MacroTotals()) { totals, meal in
            totals.calories += meal.calories
            totals.protein += meal.proteinGrams
            totals.carbs += meal.carbsGrams
            totals.fat += meal.fatGrams
        }
    }

    private var macroPercentages: (protein: Int, carbs: Int, fat: Int) {
        let sum = totals.protein + totals.carbs + totals.fat
        guard sum > 0 else { return (0, 0, 0) }
        let protein = Int((totals.protein / sum * 100).rounded())
        let carbs = Int((totals.carbs / sum * 100).rounded())
        let fat = max(0, 100 - protein - carbs)
        return (protein, carbs, fat)
    }

    private var slices: [MacroSlice] {
        [
            MacroSlice(label: "Protein", value: totals.protein, color: .macroProtein),
            MacroSlice(label: "Carbs", value: totals.carbs, color: .macroCarbs),
            MacroSlice(label: "Fat", value: totals.fat, color: .macroFat),
        ]
    }

    private var sections: [(title: String, meals: [MealEntry])] {
        groupByDate(filteredMeals)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Range", selection: $range) {
                        ForEach(RangeOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    donutCard
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .padding(.top, Theme.Spacing.sm)
                }

                ForEach(sections, id: \.title) { section in
                    Section {
                        ForEach(section.meals) { meal in
                            MealRow(meal: meal)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        delete(meal)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text(section.title)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("History")
            .overlay {
                if filteredMeals.isEmpty {
                    ContentUnavailableView(
                        "No Meals Logged",
                        systemImage: "clock",
                        description: Text("Meals you scan and save will show up here.")
                    )
                }
            }
        }
    }

    private var donutCard: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Chart {
                if totals.protein + totals.carbs + totals.fat <= 0 {
                    SectorMark(angle: .value("None", 1), innerRadius: .ratio(0.65), angularInset: 2)
                        .foregroundStyle(Color.secondary.opacity(0.2))
                } else {
                    ForEach(slices) { slice in
                        SectorMark(angle: .value(slice.label, slice.value), innerRadius: .ratio(0.65), angularInset: 2)
                            .foregroundStyle(slice.color)
                            .cornerRadius(4)
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(width: 120, height: 120)
            .overlay {
                VStack(spacing: 2) {
                    Text(range.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(totals.calories.rounded()))")
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()
                    Text("kcal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                legendRow(color: .macroProtein, label: "Protein", percent: macroPercentages.protein)
                legendRow(color: .macroCarbs, label: "Carbs", percent: macroPercentages.carbs)
                legendRow(color: .macroFat, label: "Fat", percent: macroPercentages.fat)
            }

            Spacer(minLength: 0)
        }
        .cardStyle()
    }

    private func legendRow(color: Color, label: String, percent: Int) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("\(percent)%")
                .font(.footnote)
                .fontWeight(.semibold)
        }
    }

    private func groupByDate(_ meals: [MealEntry]) -> [(title: String, meals: [MealEntry])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: meals) { calendar.startOfDay(for: $0.timestamp) }
        return groups.keys.sorted(by: >).map { day in
            let title: String
            if calendar.isDateInToday(day) {
                title = "TODAY"
            } else if calendar.isDateInYesterday(day) {
                title = "YESTERDAY"
            } else {
                title = day.formatted(.dateTime.month(.abbreviated).day()).uppercased()
            }
            let mealsForDay = (groups[day] ?? []).sorted { $0.timestamp > $1.timestamp }
            return (title, mealsForDay)
        }
    }

    private func delete(_ meal: MealEntry) {
        withAnimation {
            modelContext.delete(meal)
        }
    }
}

#Preview {
    MealHistoryView()
        .modelContainer(for: MealEntry.self, inMemory: true)
}
