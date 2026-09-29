//
//  HealthService.swift
//  NutriVision
//
//  HealthKit bridge: writes logged nutrition, water and weight, and reads
//  active energy, steps and weight. Behind a protocol so view models can be
//  tested with a stub and the app still runs where Health is unavailable
//  (iPad, simulator without data, permission denied).
//

import Foundation
import HealthKit
import os

nonisolated protocol HealthStoring: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async -> Bool
    func save(meal: MealEntry) async
    func saveWater(milliliters: Double, date: Date) async
    func saveWeight(kilograms: Double, date: Date) async
    func todayActiveEnergy() async -> Double?
    func todaySteps() async -> Double?
    func weightHistory(days: Int) async -> [WeightPoint]
}

/// Plain values copied off the SwiftData model so nothing main-actor-bound
/// crosses into the HealthKit queue.
nonisolated struct NutritionSample: Sendable {
    let id: UUID
    let date: Date
    let calories, protein, carbs, fat, fiber, sugar, sodiumMg, saturatedFat: Double

    init(meal: MealEntry) {
        id = meal.id; date = meal.timestamp; calories = meal.calories; protein = meal.proteinGrams
        carbs = meal.carbsGrams; fat = meal.fatGrams; fiber = meal.fiberGrams; sugar = meal.sugarGrams
        sodiumMg = meal.sodiumMg; saturatedFat = meal.saturatedFatGrams
    }
}

nonisolated final class HealthKitService: HealthStoring, @unchecked Sendable {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static func quantity(_ id: HKQuantityTypeIdentifier) -> HKQuantityType { HKQuantityType(id) }

    private var writeTypes: Set<HKSampleType> {
        [.dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal, .dietaryFiber,
         .dietarySugar, .dietarySodium, .dietaryFatSaturated, .dietaryWater, .bodyMass].reduce(into: []) {
            $0.insert(Self.quantity($1))
        }
    }

    private var readTypes: Set<HKObjectType> {
        [Self.quantity(.activeEnergyBurned), Self.quantity(.stepCount), Self.quantity(.bodyMass)]
    }

    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            return true
        } catch {
            Log.health.error("HealthKit authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Samples carry a sync identifier, so re-saving an edited meal replaces
    /// its earlier values instead of double counting.
    func save(meal: MealEntry) async {
        await save(NutritionSample(meal: meal))
    }

    func save(_ meal: NutritionSample) async {
        guard isAvailable else { return }
        let entries: [(HKQuantityTypeIdentifier, HKUnit, Double, String)] = [
            (.dietaryEnergyConsumed, .kilocalorie(), meal.calories, "energy"),
            (.dietaryProtein, .gram(), meal.protein, "protein"),
            (.dietaryCarbohydrates, .gram(), meal.carbs, "carbs"),
            (.dietaryFatTotal, .gram(), meal.fat, "fat"),
            (.dietaryFiber, .gram(), meal.fiber, "fiber"),
            (.dietarySugar, .gram(), meal.sugar, "sugar"),
            (.dietarySodium, .gramUnit(with: .milli), meal.sodiumMg, "sodium"),
            (.dietaryFatSaturated, .gram(), meal.saturatedFat, "satfat"),
        ]
        let samples = entries.filter { $0.2 > 0 }.map { id, unit, value, key in
            HKQuantitySample(
                type: Self.quantity(id), quantity: HKQuantity(unit: unit, doubleValue: value),
                start: meal.date, end: meal.date,
                metadata: [HKMetadataKeySyncIdentifier: "\(meal.id)-\(key)", HKMetadataKeySyncVersion: Int(Date().timeIntervalSince1970)]
            )
        }
        guard !samples.isEmpty else { return }
        do { try await store.save(samples) } catch { Log.health.error("Saving meal failed: \(error.localizedDescription)") }
    }

    func saveWater(milliliters: Double, date: Date) async {
        guard isAvailable, milliliters > 0 else { return }
        let sample = HKQuantitySample(type: Self.quantity(.dietaryWater),
                                      quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: milliliters),
                                      start: date, end: date)
        try? await store.save(sample)
    }

    func saveWeight(kilograms: Double, date: Date) async {
        guard isAvailable, kilograms > 0 else { return }
        let sample = HKQuantitySample(type: Self.quantity(.bodyMass),
                                      quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms),
                                      start: date, end: date)
        try? await store.save(sample)
    }

    func todayActiveEnergy() async -> Double? {
        await todaySum(.activeEnergyBurned, unit: .kilocalorie())
    }

    func todaySteps() async -> Double? {
        await todaySum(.stepCount, unit: .count())
    }

    private func todaySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard isAvailable else { return nil }
        let type = Self.quantity(id)
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: Date()), end: Date())
        let descriptor = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: type, predicate: predicate), options: .cumulativeSum)
        return try? await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: unit)
    }

    func weightHistory(days: Int) async -> [WeightPoint] {
        guard isAvailable else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        let type = Self.quantity(.bodyMass)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = (try? await descriptor.result(for: store)) ?? []
        return samples.map { WeightPoint(date: $0.startDate, kilograms: $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }
}

/// Used in tests and previews.
nonisolated struct NoopHealthService: HealthStoring {
    var isAvailable: Bool { false }
    func requestAuthorization() async -> Bool { false }
    func save(meal: MealEntry) async {}
    func saveWater(milliliters: Double, date: Date) async {}
    func saveWeight(kilograms: Double, date: Date) async {}
    func todayActiveEnergy() async -> Double? { nil }
    func todaySteps() async -> Double? { nil }
    func weightHistory(days: Int) async -> [WeightPoint] { [] }
}
