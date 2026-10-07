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
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("History").font(.largeTitle.bold()).padding(.top, Theme.Spacing.lg)

                searchField
                rangePicker
                donutCard

                if filteredMeals.isEmpty {
                    emptyState
                }

                ForEach(sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(section.title)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.Spacing.md)
                        ForEach(section.meals) { meal in
                            HistoryMealCard(meal: meal, onEdit: { onEdit(meal) }, onDelete: { delete(meal) })
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollIndicators(.hidden)
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

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search meals", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Clear search")
            }
        }
        .font(.title3)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 14)
        .background(.white.opacity(0.1), in: Capsule())
    }

    private var rangePicker: some View {
        HStack(spacing: 0) {
            ForEach(RangeOption.allCases) { option in
                Button { withAnimation(.snappy(duration: 0.2)) { range = option } } label: {
                    Text(option.rawValue)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(range == option ? Color.white.opacity(0.25) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.white.opacity(0.08), in: Capsule())
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            ContentUnavailableView("No Meals Logged", systemImage: "clock",
                                   description: Text("Meals you scan and save will show up here."))
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private var donutCard: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Chart {
                if totals.protein + totals.carbs + totals.fat <= 0 {
                    SectorMark(angle: .value("None", 1), innerRadius: .ratio(0.7), angularInset: 2)
                        .foregroundStyle(Color.secondary.opacity(0.2))
                } else {
                    ForEach(slices) { slice in
                        SectorMark(angle: .value(slice.label, slice.value), innerRadius: .ratio(0.7), angularInset: 3)
                            .foregroundStyle(slice.color)
                            .cornerRadius(6)
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(width: 112, height: 112)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Macro split for the \(range.rawValue.lowercased())")
            .accessibilityValue("Protein \(macroPercentages.protein) percent, carbs \(macroPercentages.carbs) percent, fat \(macroPercentages.fat) percent")
            .overlay {
                VStack(spacing: 2) {
                    Text(range.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(totals.calories.rounded()))")
                        .font(.title2.bold())
                        .monospacedDigit()
                    Text("kcal")
                        .font(.caption)
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
                .font(.body)
                .foregroundStyle(.secondary)
            Text("\(percent)%")
                .font(.body)
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

/// One logged meal: thumbnail, name, macro dots with time, and calories.
private struct HistoryMealCard: View {
    let meal: MealEntry
    var onEdit: () -> Void
    var onDelete: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                Text(meal.name).font(.title3.weight(.semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    dot(.macroProtein, meal.proteinGrams)
                    dot(.macroCarbs, meal.carbsGrams)
                    dot(.macroFat, meal.fatGrams)
                    Text("· \(meal.timestamp.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(meal.calories.rounded()))").font(.title2.bold()).monospacedDigit()
                Text("kcal").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .cardStyle(padding: Theme.Spacing.md)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: onEdit)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to edit")
        .accessibilityAction(named: "Delete", onDelete)
    }

    private func dot(_ color: Color, _ grams: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(Int(grams.rounded()))g").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = meal.photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Text(FoodEmoji.emoji(for: meal.name))
                .font(.system(size: 30))
                .frame(width: 64, height: 64)
                .background(Color.brandPrimary.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    MealHistoryView()
        .modelContainer(for: [MealEntry.self, SavedFood.self], inMemory: true)
}
