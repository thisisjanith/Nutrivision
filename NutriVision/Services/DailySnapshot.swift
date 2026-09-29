//
//  DailySnapshot.swift
//  NutriVision
//
//  Small JSON blob of today's numbers written by the app and read by the
//  widgets, Live Activity and watch app, so they never touch the SwiftData
//  store directly.
//

import Foundation

nonisolated enum AppGroup {
    static let identifier = "group.Janith-Kavinda.NutriVision"

    /// Falls back to standard defaults when the App Group isn't provisioned
    /// (e.g. running unsigned in tests), so nothing crashes.
    static var defaults: UserDefaults { UserDefaults(suiteName: identifier) ?? .standard }
}

nonisolated struct DailySnapshot: Codable, Equatable, Sendable {
    var date: Date
    var calories: Double
    var calorieGoal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var proteinGoal: Double
    var carbsGoal: Double
    var fatGoal: Double
    var waterMl: Double
    var waterGoalMl: Double

    static let empty = DailySnapshot(
        date: Date(), calories: 0, calorieGoal: 2000, protein: 0, carbs: 0, fat: 0,
        proteinGoal: 100, carbsGoal: 250, fatGoal: 65, waterMl: 0, waterGoalMl: 2500
    )

    var caloriesRemaining: Double { max(calorieGoal - calories, 0) }
    var calorieProgress: Double { calorieGoal > 0 ? min(calories / calorieGoal, 1) : 0 }

    private static let key = "nutrivision.dailySnapshot"

    static func load(from defaults: UserDefaults = AppGroup.defaults) -> DailySnapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(DailySnapshot.self, from: data),
              Calendar.current.isDateInToday(snapshot.date) else { return .empty }
        return snapshot
    }

    func save(to defaults: UserDefaults = AppGroup.defaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

/// Fasting timer state shared with the Live Activity.
nonisolated enum FastingStore {
    private static let key = "nutrivision.fastingStart"
    private static let goalKey = "nutrivision.fastingGoalHours"

    static var start: Date? {
        get { AppGroup.defaults.object(forKey: key) as? Date }
        set { AppGroup.defaults.set(newValue, forKey: key) }
    }
    static var goalHours: Double {
        get { let v = AppGroup.defaults.double(forKey: goalKey); return v > 0 ? v : 16 }
        set { AppGroup.defaults.set(newValue, forKey: goalKey) }
    }
}
