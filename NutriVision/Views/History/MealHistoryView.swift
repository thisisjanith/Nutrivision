//
//  MealHistoryView.swift
//  NutriVision
//

import SwiftUI
import SwiftData
import Charts

enum HistoryRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    var id: String { rawValue }

    func start(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        case .month: return calendar.date(byAdding: .month, value: -1, to: startOfToday) ?? startOfToday
        }
    }
}

/// Pure filtering/grouping so the history rules can be unit-tested.
enum MealHistoryFilter {
    static func meals(_ meals: [MealEntry], range: HistoryRange, search: String = "", now: Date = Date(), calendar: Calendar = .current) -> [MealEntry] {
        let start = range.start(now: now, calendar: calendar)
        let text = search.trimmingCharacters(in: .whitespaces)
        return meals.filter { meal in
            meal.timestamp >= start && (text.isEmpty || meal.name.localizedCaseInsensitiveContains(text))
        }
    }

    static func groupByDate(_ meals: [MealEntry], now: Date = Date(), calendar: Calendar = .current) -> [(title: String, meals: [MealEntry])] {
        let groups = Dictionary(grouping: meals) { calendar.startOfDay(for: $0.timestamp) }
        return groups.keys.sorted(by: >).map { day in
            let title: String
            if calendar.isDate(day, inSameDayAs: now) {
                title = "TODAY"
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)), calendar.isDate(day, inSameDayAs: yesterday) {
                title = "YESTERDAY"
            } else {
                title = day.formatted(.dateTime.month(.abbreviated).day()).uppercased()
            }
            return (title, (groups[day] ?? []).sorted { $0.timestamp > $1.timestamp })
        }
    }
}

/// Values needed to put a just-deleted meal back.
private struct DeletedMeal {
    let id: UUID, name: String, timestamp: Date, calories, protein, carbs, fat: Double
    let confidence: Double, serving: String, mealType: MealType
    let fiber, sugar, sodium, satFat: Double
    let photo: Data?

    init(_ m: MealEntry) {
        id = m.id; name = m.name; timestamp = m.timestamp; calories = m.calories; protein = m.proteinGrams
        carbs = m.carbsGrams; fat = m.fatGrams; confidence = m.confidenceScore; serving = m.servingSize
        mealType = m.mealType; fiber = m.fiberGrams; sugar = m.sugarGrams; sodium = m.sodiumMg
        satFat = m.saturatedFatGrams; photo = m.photoData
    }

    func restore() -> MealEntry {
        let entry = MealEntry(name: name, calories: calories, protein: protein, carbs: carbs, fat: fat, confidence: confidence,
                              servingSize: serving, mealType: mealType, timestamp: timestamp, fiber: fiber, sugar: sugar,
                              sodiumMg: sodium, saturatedFat: satFat, photoData: photo)
        entry.id = id
        return entry
    }
}

struct MealHistoryView: View {
    typealias RangeOption = HistoryRange

    var onEdit: (MealEntry) -> Void = { _ in }

    private struct MacroSlice: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let color: Color
    }

    @Query(sort: \MealEntry.timestamp, order: .reverse) private var allMeals: [MealEntry]
    @Environment(\.modelContext) private var modelContext
    @State private var range: RangeOption = .week
    @State private var searchText = ""
    @State private var lastDeleted: DeletedMeal?

    private var filteredMeals: [MealEntry] {
        MealHistoryFilter.meals(allMeals, range: range, search: searchText)
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
        MealHistoryFilter.groupByDate(filteredMeals)
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
                            MealRow(meal: meal, onEdit: { onEdit(meal) })
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
            .searchable(text: $searchText, prompt: "Search meals")
            .overlay {
                if filteredMeals.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView(
                            "No Meals Logged",
                            systemImage: "clock",
                            description: Text("Meals you scan and save will show up here.")
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if lastDeleted != nil {
                    HStack {
                        Text("Meal deleted")
                        Spacer()
                        Button("Undo", action: undoDelete).fontWeight(.semibold)
                    }
                    .padding(Theme.Spacing.md)
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .padding(Theme.Spacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Macro split for the \(range.rawValue.lowercased())")
            .accessibilityValue("Protein \(macroPercentages.protein) percent, carbs \(macroPercentages.carbs) percent, fat \(macroPercentages.fat) percent")
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

    private func delete(_ meal: MealEntry) {
        lastDeleted = DeletedMeal(meal)
        withAnimation {
            modelContext.delete(meal)
            Tracker.shared.mealDeleted(context: modelContext)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let deletedID = meal.id
        Task {
            try? await Task.sleep(for: .seconds(6))
            if lastDeleted?.id == deletedID { withAnimation { lastDeleted = nil } }
        }
    }

    private func undoDelete() {
        guard let deleted = lastDeleted else { return }
        let entry = deleted.restore()
        modelContext.insert(entry)
        Tracker.shared.mealSaved(entry, context: modelContext)
        withAnimation { lastDeleted = nil }
    }
}

#Preview {
    MealHistoryView()
        .modelContainer(for: [MealEntry.self, SavedFood.self], inMemory: true)
}
