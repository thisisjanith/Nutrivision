//
//  DashboardView.swift
//  NutriVision
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    var onAddFood: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onEdit: (MealEntry) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Query private var todayMeals: [MealEntry]
    @Query private var todayWater: [WaterEntry]
    @State private var viewModel = DashboardViewModel()
    private let tracker = Tracker.shared
    private let fasting = FastingController.shared

    init(onAddFood: @escaping () -> Void = {}, onOpenSettings: @escaping () -> Void = {}, onEdit: @escaping (MealEntry) -> Void = { _ in }) {
        self.onAddFood = onAddFood
        self.onOpenSettings = onOpenSettings
        self.onEdit = onEdit
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _todayMeals = Query(
            filter: #Predicate<MealEntry> { $0.timestamp >= start && $0.timestamp < end },
            sort: \MealEntry.timestamp,
            order: .reverse
        )
        _todayWater = Query(filter: #Predicate<WaterEntry> { $0.date >= start && $0.date < end })
    }

    private var totals: DashboardViewModel.MacroTotals {
        viewModel.macroTotals(for: todayMeals)
    }

    private var waterMl: Double { todayWater.reduce(0) { $0 + $1.milliliters } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                summaryCard
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    waterCard
                    fastingCard
                }
                if tracker.profileStore.profile.syncToHealth { activityCard }
                mealsSection
            }
            .padding(Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .background(Color(.systemGroupedBackground))
        .scrollIndicators(.hidden)
        .task { await tracker.refreshActivity() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(viewModel.greeting)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(viewModel.formattedToday)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onAddFood) {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Color.brandPrimary, in: Circle())
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Add food")
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(Color.cardBackground, in: Circle())
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Settings")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Summary

    private var summaryCard: some View {
        VStack(spacing: Theme.Spacing.lg) {
            MacroRingView(
                proteinGrams: totals.protein,
                carbsGrams: totals.carbs,
                fatGrams: totals.fat,
                totalCalories: totals.calories,
                goals: viewModel.goals
            )
            .frame(maxWidth: 220)
            .frame(maxWidth: .infinity)

            macroGoalBars

            calorieGoalBar
        }
        .cardStyle()
    }

    private var macroGoalBars: some View {
        let goals = viewModel.goals
        return VStack(spacing: Theme.Spacing.sm) {
            macroBar("Protein", value: totals.protein, goal: goals.protein, color: .macroProtein)
            macroBar("Carbs", value: totals.carbs, goal: goals.carbs, color: .macroCarbs)
            macroBar("Fat", value: totals.fat, goal: goals.fat, color: .macroFat)
        }
    }

    private func macroBar(_ label: String, value: Double, goal: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: Theme.Spacing.xs) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(label).font(.footnote)
                }
                Spacer()
                Text("\(Int(value.rounded())) / \(Int(goal.rounded())) g")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: min(value, max(goal, 1)), total: max(goal, 1))
                .tint(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value.rounded())) of \(Int(goal.rounded())) grams")
    }

    private var calorieGoalBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Calorie Goal")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(totals.calories.rounded())) / \(Int(viewModel.calorieGoal.rounded())) kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.brandPrimary.opacity(0.15))
                    Capsule()
                        .fill(Color.brandPrimary)
                        .frame(width: proxy.size.width * viewModel.goalProgress(consumed: totals.calories))
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: totals.calories)
                }
            }
            .frame(height: 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Calorie goal progress")
            .accessibilityValue("\(Int(totals.calories.rounded())) of \(Int(viewModel.calorieGoal.rounded())) kilocalories")
        }
    }

    // MARK: Side cards

    private var waterCard: some View {
        let goal = tracker.profileStore.waterGoalMl
        let units = tracker.profileStore.profile.units
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Water", systemImage: "drop.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
            Text(units.waterText(ml: waterMl))
                .font(.title3.bold())
                .monospacedDigit()
            ProgressView(value: min(waterMl, max(goal, 1)), total: max(goal, 1)).tint(.blue)
            Text("of \(units.waterText(ml: goal))").font(.caption).foregroundStyle(.secondary)
            HStack {
                waterButton(250)
                waterButton(500)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: Theme.Spacing.sm)
        .accessibilityElement(children: .contain)
    }

    private func waterButton(_ ml: Double) -> some View {
        Button {
            Tracker.shared.addWater(milliliters: ml, context: modelContext)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text("+\(Int(ml))")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(Int(ml)) milliliters of water")
    }

    private var fastingCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Fasting", systemImage: "timer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.purple)
            if let start = fasting.startDate, let end = fasting.endDate {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let elapsed = context.date.timeIntervalSince(start)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.duration(elapsed)).font(.title3.bold()).monospacedDigit()
                        ProgressView(value: min(max(elapsed, 0), end.timeIntervalSince(start)), total: end.timeIntervalSince(start)).tint(.purple)
                        Text(elapsed >= end.timeIntervalSince(start) ? "Goal reached" : "Ends \(end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("End fast") { fasting.stop() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
            } else {
                Text("\(Int(fasting.goalHours)) h").font(.title3.bold())
                Stepper("Goal", value: Binding(get: { fasting.goalHours }, set: { fasting.goalHours = $0 }), in: 8...24, step: 1)
                    .labelsHidden()
                Button("Start fast") { fasting.start() }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: Theme.Spacing.sm)
    }

    private static func duration(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    private var activityCard: some View {
        HStack {
            Label("\(Int((tracker.activeEnergyToday ?? 0).rounded())) kcal active", systemImage: "flame.fill")
                .foregroundStyle(.orange)
            Spacer()
            Label("\(Int((tracker.stepsToday ?? 0).rounded())) steps", systemImage: "figure.walk")
                .foregroundStyle(Color.brandPrimary)
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity)
        .cardStyle(padding: Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    // MARK: Meals

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Today's Meals")
                .font(.headline)

            if todayMeals.isEmpty {
                ContentUnavailableView {
                    Label("No meals yet", systemImage: "fork.knife")
                } description: {
                    Text("Tap Scan to log your first meal, or search for a food.")
                } actions: {
                    Button("Add food", action: onAddFood).buttonStyle(.borderedProminent).tint(Color.brandPrimary)
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(viewModel.groupedByMealType(todayMeals), id: \.type) { group in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack {
                            Label(group.type.title, systemImage: group.type.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(group.meals.reduce(0) { $0 + $1.calories }.rounded())) kcal")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 0) {
                            ForEach(group.meals) { meal in
                                MealRow(meal: meal, onEdit: { onEdit(meal) })
                                if meal.id != group.meals.last?.id { Divider() }
                            }
                        }
                        .cardStyle(padding: Theme.Spacing.sm)
                    }
                }
            }
        }
    }
}

struct MealRow: View {
    let meal: MealEntry
    var onEdit: (() -> Void)?

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(meal.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(Int(meal.calories.rounded())) kcal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.sm)
        .contentShape(Rectangle())
        .onTapGesture { onEdit?() }
        .contextMenu {
            if let onEdit { Button("Edit", systemImage: "pencil", action: onEdit) }
            Button("Save as favorite", systemImage: "star") {
                modelContext.insert(SavedFood(
                    name: meal.name, calories: meal.calories, protein: meal.proteinGrams, carbs: meal.carbsGrams,
                    fat: meal.fatGrams, servingSize: meal.servingSize, isFavorite: true, fiber: meal.fiberGrams,
                    sugar: meal.sugarGrams, sodiumMg: meal.sodiumMg, saturatedFat: meal.saturatedFatGrams))
                try? modelContext.save()
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                modelContext.delete(meal)
                Tracker.shared.mealDeleted(context: modelContext)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(onEdit == nil ? "" : "Double tap to edit")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = meal.photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .accessibilityHidden(true)
        } else {
            Circle()
                .fill(Color.brandPrimary.opacity(0.15))
                .overlay {
                    Image(systemName: meal.mealType.systemImage)
                        .font(.footnote)
                        .foregroundStyle(Color.brandPrimary)
                }
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [MealEntry.self, WaterEntry.self], inMemory: true)
}
