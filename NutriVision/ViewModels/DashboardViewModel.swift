//
//  DashboardViewModel.swift
//  NutriVision
//

import Foundation
import Observation

@Observable
final class DashboardViewModel {
    private enum DefaultsKey {
        static let userName = "nutrivision.userName"
        static let calorieGoal = "nutrivision.calorieGoal"
    }

    private let defaults: UserDefaults

    var userName: String {
        didSet { defaults.set(userName, forKey: DefaultsKey.userName) }
    }

    var calorieGoal: Double {
        didSet { defaults.set(calorieGoal, forKey: DefaultsKey.calorieGoal) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.userName = defaults.string(forKey: DefaultsKey.userName) ?? "there"
        let storedGoal = defaults.double(forKey: DefaultsKey.calorieGoal)
        self.calorieGoal = storedGoal > 0 ? storedGoal : 1800
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning, \(userName)"
        case 12..<17: return "Good afternoon, \(userName)"
        default: return "Good evening, \(userName)"
        }
    }

    var formattedToday: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    struct MacroTotals {
        var calories: Double = 0
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
    }

    func macroTotals(for meals: [MealEntry]) -> MacroTotals {
        meals.reduce(into: MacroTotals()) { totals, meal in
            totals.calories += meal.calories
            totals.protein += meal.proteinGrams
            totals.carbs += meal.carbsGrams
            totals.fat += meal.fatGrams
        }
    }

    func goalProgress(consumed: Double) -> Double {
        guard calorieGoal > 0 else { return 0 }
        return min(max(consumed / calorieGoal, 0), 1)
    }
}
