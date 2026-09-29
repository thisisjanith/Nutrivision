//
//  DashboardViewModel.swift
//  NutriVision
//

import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let profileStore: ProfileStore

    init(profileStore: ProfileStore? = nil) {
        self.profileStore = profileStore ?? .shared
    }

    var userName: String {
        let name = profileStore.profile.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "there" : name
    }

    var goals: MacroGoals { profileStore.goals }
    var calorieGoal: Double { goals.calories }

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

    /// Meals grouped by meal type in day order, skipping empty groups.
    func groupedByMealType(_ meals: [MealEntry]) -> [(type: MealType, meals: [MealEntry])] {
        MealType.allCases.compactMap { type in
            let group = meals.filter { $0.mealType == type }
            return group.isEmpty ? nil : (type, group)
        }
    }
}
