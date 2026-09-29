//
//  WeightView.swift
//  NutriVision
//

import SwiftUI
import SwiftData
import Charts

struct WeightView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \WaterEntry.date, order: .reverse) private var water: [WaterEntry]
    @Query private var meals: [MealEntry]

    @State private var showAdd = false
    @State private var newWeight = 0.0
    @State private var importedCount: Int?
    private let store = ProfileStore.shared

    private var units: UnitSystem { store.profile.units }
    private var points: [WeightPoint] { weights.map { WeightPoint(date: $0.date, kilograms: $0.kilograms) } }
    private var trend: [WeightPoint] { WeightTrend.smoothed(points) }

    private var eta: Date? {
        guard let latest = trend.last, let slope = WeightTrend.slopeKgPerDay(Array(trend.suffix(28))) else { return nil }
        return WeightTrend.etaToGoal(current: latest.kilograms, target: store.profile.targetWeightKg, slopeKgPerDay: slope)
    }

    private var suggestion: AdaptiveGoal.Suggestion? {
        let calendar = Calendar.current
        var intake: [Date: Double] = [:]
        for meal in meals { intake[calendar.startOfDay(for: meal.timestamp), default: 0] += meal.calories }
        return AdaptiveGoal.suggestion(weights: points, intakeByDay: intake, profile: store.profile, currentTarget: store.goals.calories)
    }

    private var todayWater: Double {
        water.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.milliliters }
    }

    var body: some View {
        List {
            Section {
                chart
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                summaryRow
            }

            if let suggestion {
                Section("Adaptive goal") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Based on your weight trend and intake, you burn about \(Int(suggestion.estimatedMaintenance)) kcal a day.")
                            .font(.subheadline)
                        Button("Set daily goal to \(Int(suggestion.suggestedCalories)) kcal") {
                            store.profile.calorieOverride = suggestion.suggestedCalories
                            Tracker.shared.refreshSnapshot(context: modelContext)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.brandPrimary)
                    }
                }
            }

            Section("Water today") {
                HStack {
                    Text("\(units.waterText(ml: todayWater)) of \(units.waterText(ml: store.waterGoalMl))")
                    Spacer()
                    Button("+250 ml") { Tracker.shared.addWater(milliliters: 250, context: modelContext) }
                        .buttonStyle(.bordered)
                }
            }

            Section("Weigh-ins") {
                if weights.isEmpty {
                    ContentUnavailableView("No weigh-ins yet", systemImage: "scalemass",
                                           description: Text("Add your weight to see your trend."))
                }
                ForEach(weights.reversed()) { entry in
                    HStack {
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text(units.weightText(kg: entry.kilograms)).monospacedDigit()
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            modelContext.delete(entry)
                            try? modelContext.save()
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }

            if store.profile.syncToHealth {
                Section {
                    Button("Import weights from Apple Health", systemImage: "heart.text.square") {
                        Task { importedCount = await Tracker.shared.importWeights(context: modelContext) }
                    }
                    if let importedCount { Text("Imported \(importedCount) weigh-ins.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Weight")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") {
                    newWeight = units.displayWeight(kg: weights.last?.kilograms ?? store.profile.weightKg)
                    showAdd = true
                }
            }
        }
        .sheet(isPresented: $showAdd) { addSheet }
    }

    private var chart: some View {
        Chart {
            ForEach(Array(weights.enumerated()), id: \.offset) { _, entry in
                PointMark(x: .value("Date", entry.date), y: .value("Weight", units.displayWeight(kg: entry.kilograms)))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            ForEach(Array(trend.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("Date", point.date), y: .value("Trend", units.displayWeight(kg: point.kilograms)))
                    .foregroundStyle(Color.brandPrimary)
                    .interpolationMethod(.catmullRom)
            }
            if store.profile.goal != .maintain {
                RuleMark(y: .value("Target", units.displayWeight(kg: store.profile.targetWeightKg)))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 200)
        .accessibilityLabel("Weight over time")
        .accessibilityValue(weights.last.map { "Latest \(units.weightText(kg: $0.kilograms))" } ?? "No data")
    }

    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let latest = trend.last {
                Text("Trend weight: \(units.weightText(kg: latest.kilograms))").font(.subheadline.weight(.semibold))
            }
            if let slope = WeightTrend.slopeKgPerDay(Array(trend.suffix(28))) {
                let perWeek = slope * 7
                Text("\(perWeek >= 0 ? "+" : "")\(units.weightText(kg: abs(perWeek)).replacingOccurrences(of: "-", with: "")) per week")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if store.profile.goal != .maintain {
                if let eta {
                    Text("On track to reach \(units.weightText(kg: store.profile.targetWeightKg)) around \(eta.formatted(date: .abbreviated, time: .omitted)).")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if weights.count >= 2 {
                    Text("Your trend isn't heading toward your goal yet.").font(.footnote).foregroundStyle(.orange)
                }
            }
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                NumberField(title: "Weight", value: $newWeight, unit: units.weightUnit)
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAdd = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Tracker.shared.addWeight(kilograms: units.kilograms(fromDisplay: newWeight), context: modelContext)
                        showAdd = false
                    }
                    .disabled(newWeight <= 0)
                }
            }
        }
        .presentationDetents([.height(220)])
    }
}
