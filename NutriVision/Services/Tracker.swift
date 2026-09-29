//
//  Tracker.swift
//  NutriVision
//
//  The one place that mutates logged data with side effects: after a meal,
//  water or weight entry is saved it mirrors to HealthKit, refreshes the
//  shared snapshot the widgets/watch read, and reloads their timelines.
//

import Foundation
import SwiftData
import Observation
import WidgetKit

@MainActor
@Observable
final class Tracker {
    static let shared = Tracker()

    var health: any HealthStoring
    let profileStore: ProfileStore

    private(set) var activeEnergyToday: Double?
    private(set) var stepsToday: Double?

    init(health: any HealthStoring = HealthKitService(), profileStore: ProfileStore? = nil) {
        self.health = health
        self.profileStore = profileStore ?? .shared
    }

    // MARK: Meals

    func mealSaved(_ meal: MealEntry, context: ModelContext) {
        try? context.save()
        if profileStore.profile.syncToHealth {
            let sample = NutritionSample(meal: meal)
            let health = self.health
            Task {
                if let service = health as? HealthKitService { await service.save(sample) } else { await health.save(meal: meal) }
            }
        }
        refreshSnapshot(context: context)
    }

    func mealDeleted(context: ModelContext) {
        try? context.save()
        refreshSnapshot(context: context)
    }

    // MARK: Water

    func addWater(milliliters: Double, context: ModelContext, date: Date = Date()) {
        context.insert(WaterEntry(milliliters: milliliters, date: date))
        try? context.save()
        if profileStore.profile.syncToHealth {
            let health = self.health
            Task { await health.saveWater(milliliters: milliliters, date: date) }
        }
        refreshSnapshot(context: context)
    }

    // MARK: Weight

    func addWeight(kilograms: Double, context: ModelContext, date: Date = Date()) {
        context.insert(WeightEntry(kilograms: kilograms, date: date))
        try? context.save()
        // The latest weigh-in drives the calorie formula.
        if let latest = try? context.fetch(FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])).first {
            profileStore.profile.weightKg = latest.kilograms
        }
        if profileStore.profile.syncToHealth {
            let health = self.health
            Task { await health.saveWeight(kilograms: kilograms, date: date) }
        }
        refreshSnapshot(context: context)
    }

    // MARK: Health

    func enableHealthSync() async -> Bool {
        let granted = await health.requestAuthorization()
        profileStore.profile.syncToHealth = granted
        if granted { await refreshActivity() }
        return granted
    }

    func refreshActivity() async {
        guard profileStore.profile.syncToHealth else { return }
        activeEnergyToday = await health.todayActiveEnergy()
        stepsToday = await health.todaySteps()
    }

    /// Pulls weigh-ins recorded in Apple Health (e.g. from a smart scale) into
    /// the local log, skipping ones already present.
    func importWeights(context: ModelContext) async -> Int {
        let points = await health.weightHistory(days: 120)
        let existing = ((try? context.fetch(FetchDescriptor<WeightEntry>())) ?? []).map(\.date)
        var added = 0
        for point in points where !existing.contains(where: { abs($0.timeIntervalSince(point.date)) < 60 }) {
            context.insert(WeightEntry(kilograms: point.kilograms, date: point.date))
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }

    // MARK: Snapshot

    func refreshSnapshot(context: ModelContext) {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let meals = (try? context.fetch(FetchDescriptor<MealEntry>(predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end }))) ?? []
        let water = (try? context.fetch(FetchDescriptor<WaterEntry>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        let goals = profileStore.goals

        DailySnapshot(
            date: Date(),
            calories: meals.reduce(0) { $0 + $1.calories },
            calorieGoal: goals.calories,
            protein: meals.reduce(0) { $0 + $1.proteinGrams },
            carbs: meals.reduce(0) { $0 + $1.carbsGrams },
            fat: meals.reduce(0) { $0 + $1.fatGrams },
            proteinGoal: goals.protein, carbsGoal: goals.carbs, fatGoal: goals.fat,
            waterMl: water.reduce(0) { $0 + $1.milliliters },
            waterGoalMl: profileStore.waterGoalMl
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
        WatchBridge.shared.pushSnapshot()
    }
}
