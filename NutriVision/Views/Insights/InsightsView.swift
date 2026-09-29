//
//  InsightsView.swift
//  NutriVision
//

import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    enum Range: Int, CaseIterable, Identifiable {
        case week = 7, month = 30
        var id: Int { rawValue }
        var title: String { self == .week ? "Week" : "Month" }
    }

    private struct MacroPoint: Identifiable {
        let id = UUID()
        let date: Date
        let macro: String
        let kcal: Double
    }

    @Query(sort: \MealEntry.timestamp) private var meals: [MealEntry]
    @Query(sort: \WaterEntry.date) private var water: [WaterEntry]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    @State private var range: Range = .week
    @State private var shareItem: URL?
    private let store = ProfileStore.shared

    private var goals: MacroGoals { store.goals }
    private var days: [DayTotal] { InsightsEngine.dailyTotals(meals: meals, days: range.rawValue) }
    private var lastSeven: [DayTotal] { InsightsEngine.dailyTotals(meals: meals, days: 7) }
    private var streakDays: [DayTotal] { InsightsEngine.dailyTotals(meals: meals, days: 120) }

    private var waterAverage: Double? {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let recent = water.filter { $0.date >= start }
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0) { $0 + $1.milliliters } / 7
    }

    private var macroPoints: [MacroPoint] {
        days.flatMap { day in
            [MacroPoint(date: day.date, macro: "Protein", kcal: day.protein * 4),
             MacroPoint(date: day.date, macro: "Carbs", kcal: day.carbs * 4),
             MacroPoint(date: day.date, macro: "Fat", kcal: day.fat * 9)]
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    statTiles
                    insightCards
                    calorieChart
                    macroChart
                    weightLink
                }
                .padding(Theme.Spacing.md)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Export CSV", systemImage: "tablecells") { shareItem = try? ExportService.writeCSV(meals: meals) }
                        Button("Export PDF", systemImage: "doc.richtext") { shareItem = try? ExportService.writePDF(meals: meals) }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export data")
                }
            }
            .sheet(item: $shareItem) { url in ActivityView(items: [url]) }
        }
    }

    // MARK: Tiles + cards

    private var statTiles: some View {
        let streak = InsightsEngine.currentStreak(streakDays)
        let best = InsightsEngine.longestStreak(streakDays)
        let score = InsightsEngine.consistencyScore(days, calorieGoal: goals.calories)
        return HStack(spacing: Theme.Spacing.sm) {
            tile("flame.fill", "\(streak)", "day streak", .orange)
            tile("trophy.fill", "\(best)", "best streak", .yellow)
            tile("checkmark.seal.fill", "\(score)", "consistency", Color.brandPrimary)
        }
    }

    private func tile(_ icon: String, _ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    private var insightCards: some View {
        let cards = InsightsEngine.cards(days: lastSeven, goals: goals, streak: InsightsEngine.currentStreak(streakDays),
                                         waterAverageMl: waterAverage, waterGoalMl: store.waterGoalMl)
        return VStack(spacing: Theme.Spacing.sm) {
            ForEach(cards) { card in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: card.systemImage)
                        .foregroundStyle(color(for: card.tone))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.title).font(.subheadline.weight(.semibold))
                        Text(card.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle(padding: Theme.Spacing.sm)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func color(for tone: InsightCard.Tone) -> Color {
        switch tone {
        case .good: Color.brandPrimary
        case .neutral: .blue
        case .warning: .orange
        }
    }

    // MARK: Charts

    private var calorieChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Calories").font(.headline)
            Chart {
                ForEach(days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("kcal", day.calories))
                        .foregroundStyle(day.calories > goals.calories * 1.15 ? Color.orange : Color.brandPrimary)
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Goal", goals.calories))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal \(Int(goals.calories))").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 7)) { _ in
                AxisValueLabel(format: range == .week ? .dateTime.weekday(.narrow) : .dateTime.month().day())
            } }
            .frame(height: 180)
            .accessibilityLabel("Calories per day")
            .accessibilityValue(calorieSummary)
        }
        .cardStyle()
    }

    private var calorieSummary: String {
        let logged = days.filter(\.isLogged)
        guard !logged.isEmpty else { return "No data" }
        let average = logged.reduce(0) { $0 + $1.calories } / Double(logged.count)
        return "Average \(Int(average.rounded())) kilocalories on \(logged.count) logged days. Goal \(Int(goals.calories))."
    }

    private var macroChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Macros").font(.headline)
            Chart(macroPoints) { point in
                BarMark(x: .value("Day", point.date, unit: .day), y: .value("kcal", point.kcal))
                    .foregroundStyle(by: .value("Macro", point.macro))
            }
            .chartForegroundStyleScale(["Protein": Color.macroProtein, "Carbs": Color.macroCarbs, "Fat": Color.macroFat])
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 7)) { _ in
                AxisValueLabel(format: range == .week ? .dateTime.weekday(.narrow) : .dateTime.month().day())
            } }
            .frame(height: 180)
            .accessibilityLabel("Calories from protein, carbs and fat per day")
            .accessibilityValue(macroSummary)
        }
        .cardStyle()
    }

    private var macroSummary: String {
        let logged = days.filter(\.isLogged)
        guard !logged.isEmpty else { return "No data" }
        let n = Double(logged.count)
        return "Daily average: protein \(Int((logged.reduce(0) { $0 + $1.protein } / n).rounded())) grams, carbs \(Int((logged.reduce(0) { $0 + $1.carbs } / n).rounded())) grams, fat \(Int((logged.reduce(0) { $0 + $1.fat } / n).rounded())) grams."
    }

    private var weightLink: some View {
        NavigationLink {
            WeightView()
        } label: {
            HStack {
                Image(systemName: "scalemass.fill").foregroundStyle(Color.brandPrimary)
                VStack(alignment: .leading) {
                    Text("Weight & water").font(.subheadline.weight(.semibold))
                    Text(weights.last.map { "Latest \(store.profile.units.weightText(kg: $0.kilograms))" } ?? "Log your first weigh-in")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// UIKit share sheet for a freshly written export file.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
