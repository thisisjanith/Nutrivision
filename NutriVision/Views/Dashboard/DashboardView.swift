//
//  DashboardView.swift
//  NutriVision
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    var onAddFood: () -> Void = {}
    var onScan: () -> Void = {}
    var onEdit: (MealEntry) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @Query private var todayMeals: [MealEntry]
    @Query private var todayWater: [WaterEntry]
    @State private var viewModel = DashboardViewModel()
    private let tracker = Tracker.shared
    private let fasting = FastingController.shared

    init(onAddFood: @escaping () -> Void = {}, onScan: @escaping () -> Void = {}, onEdit: @escaping (MealEntry) -> Void = { _ in }) {
        self.onAddFood = onAddFood
        self.onScan = onScan
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
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header
                summaryCard
                macroTiles
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    waterCard
                    fastingCard
                }
                .fixedSize(horizontal: false, vertical: true)
                if tracker.profileStore.profile.syncToHealth { activityCard }
                mealsSection
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.md)
        }
        .scrollIndicators(.hidden)
        .task { await tracker.refreshActivity() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(viewModel.formattedToday.uppercased())
                    .font(.footnote.weight(.medium))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Text(viewModel.greeting)
                    .font(.title.bold())
            }
            Spacer()
            Button(action: onAddFood) {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .background(LinearGradient.brand, in: Circle())
                    .foregroundStyle(.white)
                    .shadow(color: Color.brandPrimary.opacity(0.5), radius: 10, y: 4)
            }
            .accessibilityLabel("Add food")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Summary

    private var summaryCard: some View {
        let goal = viewModel.calorieGoal
        let left = Int((goal - totals.calories).rounded())
        return HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: viewModel.goalProgress(consumed: totals.calories))
                    .stroke(.white, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(abs(left))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text(left >= 0 ? "kcal left" : "kcal over")
                        .font(.footnote)
                        .opacity(0.85)
                }
                .padding(Theme.Spacing.md + 8)
            }
            .frame(width: 140, height: 140)
            .padding(.vertical, Theme.Spacing.xs)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                summaryStat(icon: "fork.knife", title: "Eaten", value: Int(totals.calories.rounded()))
                summaryStat(icon: "scope", title: "Goal", value: Int(goal.rounded()))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                LinearGradient.brand
                Circle().fill(.white.opacity(0.08)).frame(width: 240).offset(x: 140, y: -90)
                Circle().fill(.white.opacity(0.06)).frame(width: 180).offset(x: -150, y: 110)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .shadow(color: Color.brandPrimary.opacity(0.35), radius: 24, y: 10)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: totals.calories)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(abs(left)) kilocalories \(left >= 0 ? "left" : "over"). Eaten \(Int(totals.calories.rounded())), goal \(Int(goal.rounded()))")
    }

    private func summaryStat(icon: String, title: String, value: Int) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.subheadline)
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.22), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.footnote).opacity(0.85)
                Text("\(value)").font(.title3.bold()).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private var macroTiles: some View {
        let goals = viewModel.goals
        return HStack(spacing: Theme.Spacing.sm) {
            macroTile("Protein", value: totals.protein, goal: goals.protein, color: .macroProtein)
            macroTile("Carbs", value: totals.carbs, goal: goals.carbs, color: .macroCarbs)
            macroTile("Fat", value: totals.fat, goal: goals.fat, color: .macroFat)
        }
    }

    private func macroTile(_ label: String, value: Double, goal: Double, color: Color) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().stroke(color.opacity(0.22), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: min(max(value / max(goal, 1), 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value.rounded()))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
            VStack(spacing: 2) {
                Text(label).font(.headline)
                Text("of \(Int(goal.rounded())) g").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: Theme.Spacing.md)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value.rounded())) of \(Int(goal.rounded())) grams")
    }

    // MARK: Side cards

    private func cardHeader(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            Text(title).font(.headline)
        }
    }

    private var waterCard: some View {
        let goal = tracker.profileStore.waterGoalMl
        let units = tracker.profileStore.profile.units
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            cardHeader("Water", systemImage: "drop.fill", color: .blue)
            Text(units.waterText(ml: waterMl))
                .font(.title.bold())
                .monospacedDigit()
            Text("of \(units.waterText(ml: goal))").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(spacing: Theme.Spacing.sm) {
                waterButton(250)
                waterButton(500)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardStyle(padding: Theme.Spacing.md)
        .accessibilityElement(children: .contain)
    }

    private func waterButton(_ ml: Double) -> some View {
        Button {
            Tracker.shared.addWater(milliliters: ml, context: modelContext)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text("+\(Int(ml))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(Int(ml)) milliliters of water")
    }

    private var fastingCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            cardHeader("Fasting", systemImage: "timer", color: .fastingPurple)
            if let start = fasting.startDate, let end = fasting.endDate {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let elapsed = context.date.timeIntervalSince(start)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.duration(elapsed)).font(.title.bold()).monospacedDigit()
                        ProgressView(value: min(max(elapsed, 0), end.timeIntervalSince(start)), total: end.timeIntervalSince(start)).tint(Color.fastingPurple)
                        Text(elapsed >= end.timeIntervalSince(start) ? "Goal reached" : "Ends \(end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button { fasting.stop() } label: {
                    Text("End fast")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(fasting.goalHours))").font(.title.bold()).monospacedDigit()
                    Text("h").font(.headline).foregroundStyle(.secondary)
                }
                Text("fasting goal").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: 0) {
                        stepButton("minus", delta: -1)
                        stepButton("plus", delta: 1)
                    }
                    .background(.white.opacity(0.1), in: Capsule())
                }
                .frame(maxWidth: .infinity)
                Button { fasting.start() } label: {
                    Text("Start fast")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.fastingPurple, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardStyle(padding: Theme.Spacing.md)
    }

    private func stepButton(_ icon: String, delta: Double) -> some View {
        Button {
            fasting.goalHours = min(max(fasting.goalHours + delta, 8), 24)
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta < 0 ? "Decrease fasting goal" : "Increase fasting goal")
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
        .cardStyle(padding: Theme.Spacing.md)
        .accessibilityElement(children: .combine)
    }

    // MARK: Meals

    private var mealsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Today's Meals")
                .font(.title2.bold())
                .padding(.top, Theme.Spacing.sm)

            if todayMeals.isEmpty {
                emptyMeals
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

    private var emptyMeals: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("🍽️")
                .font(.system(size: 40))
                .frame(width: 84, height: 84)
                .background(Color.brandPrimary.opacity(0.14), in: Circle())
            Text("Nothing logged yet").font(.title3.weight(.semibold))
            Text("Snap a photo of your meal and we'll recognise it for you.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.sm) {
                Button(action: onScan) {
                    Label("Scan a meal", systemImage: "viewfinder")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient.brand, in: Capsule())
                }
                Button(action: onAddFood) {
                    Label("Search", systemImage: "magnifyingglass")
                        .font(.headline)
                        .foregroundStyle(Color.brandPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.brandPrimary.opacity(0.14), in: Capsule())
                }
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.md)
        .cardStyle(padding: 0)
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
