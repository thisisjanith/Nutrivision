//
//  DashboardView.swift
//  NutriVision
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query private var todayMeals: [MealEntry]
    @State private var viewModel = DashboardViewModel()

    init() {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _todayMeals = Query(
            filter: #Predicate<MealEntry> { $0.timestamp >= start && $0.timestamp < end },
            sort: \MealEntry.timestamp,
            order: .reverse
        )
    }

    private var totals: DashboardViewModel.MacroTotals {
        viewModel.macroTotals(for: todayMeals)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                summaryCard
                mealsSection
            }
            .padding(Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .background(Color(.systemGroupedBackground))
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(viewModel.greeting)
                .font(.title2)
                .fontWeight(.bold)
            Text(viewModel.formattedToday)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCard: some View {
        VStack(spacing: Theme.Spacing.lg) {
            MacroRingView(
                proteinGrams: totals.protein,
                carbsGrams: totals.carbs,
                fatGrams: totals.fat,
                totalCalories: totals.calories
            )
            .frame(maxWidth: 220)
            .frame(maxWidth: .infinity)

            macroLegend

            calorieGoalBar
        }
        .cardStyle()
    }

    private var macroLegend: some View {
        HStack(spacing: Theme.Spacing.lg) {
            legendItem(color: .macroProtein, label: "Protein", value: totals.protein)
            legendItem(color: .macroCarbs, label: "Carbs", value: totals.carbs)
            legendItem(color: .macroFat, label: "Fat", value: totals.fat)
        }
        .frame(maxWidth: .infinity)
    }

    private func legendItem(color: Color, label: String, value: Double) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label) \(Int(value.rounded()))g")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
        }
    }

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Today's Meals")
                .font(.headline)

            if todayMeals.isEmpty {
                Text("No meals logged yet today. Tap Scan to log your first meal.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Spacing.md)
            } else {
                VStack(spacing: 0) {
                    ForEach(todayMeals) { meal in
                        MealRow(meal: meal)
                        if meal.id != todayMeals.last?.id {
                            Divider()
                        }
                    }
                }
                .cardStyle(padding: Theme.Spacing.sm)
            }
        }
    }
}

struct MealRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Circle()
                .fill(Color.brandPrimary.opacity(0.15))
                .overlay {
                    Image(systemName: "fork.knife")
                        .font(.footnote)
                        .foregroundStyle(Color.brandPrimary)
                }
                .frame(width: 40, height: 40)

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
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: MealEntry.self, inMemory: true)
}
