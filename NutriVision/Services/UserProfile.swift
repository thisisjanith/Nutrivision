//
//  UserProfile.swift
//  NutriVision
//
//  Body stats, goals and calorie/macro maths. The maths lives in pure
//  functions on `NutritionGoals` so it can be tested without any UI.
//

import Foundation
import Observation

nonisolated enum Sex: String, Codable, CaseIterable, Identifiable, Sendable {
    case female, male
    var id: String { rawValue }
    var title: String { self == .female ? "Female" : "Male" }
}

nonisolated enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case sedentary, light, moderate, active, veryActive
    var id: String { rawValue }

    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }

    var title: String {
        switch self {
        case .sedentary: "Sedentary"
        case .light: "Lightly active"
        case .moderate: "Moderately active"
        case .active: "Very active"
        case .veryActive: "Extra active"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: "Desk job, little exercise"
        case .light: "Exercise 1–3 days a week"
        case .moderate: "Exercise 3–5 days a week"
        case .active: "Hard exercise 6–7 days a week"
        case .veryActive: "Physical job or twice-daily training"
        }
    }
}

nonisolated enum GoalType: String, Codable, CaseIterable, Identifiable, Sendable {
    case lose, maintain, gain
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lose: "Lose weight"
        case .maintain: "Maintain weight"
        case .gain: "Gain weight"
        }
    }
}

nonisolated enum DietPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case balanced, highProtein, lowCarb, keto
    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: "Balanced"
        case .highProtein: "High protein"
        case .lowCarb: "Low carb"
        case .keto: "Keto"
        }
    }

    /// Share of calories from (protein, carbs, fat).
    var split: (protein: Double, carbs: Double, fat: Double) {
        switch self {
        case .balanced: (0.25, 0.45, 0.30)
        case .highProtein: (0.35, 0.35, 0.30)
        case .lowCarb: (0.30, 0.20, 0.50)
        case .keto: (0.25, 0.05, 0.70)
        }
    }
}

nonisolated enum UnitSystem: String, Codable, CaseIterable, Identifiable, Sendable {
    case metric, imperial
    var id: String { rawValue }
    var title: String { self == .metric ? "Metric" : "Imperial" }

    func weightText(kg: Double) -> String {
        switch self {
        case .metric: "\(kg.formatted(.number.precision(.fractionLength(1)))) kg"
        case .imperial: "\((kg * 2.20462).formatted(.number.precision(.fractionLength(1)))) lb"
        }
    }

    func heightText(cm: Double) -> String {
        switch self {
        case .metric:
            return "\(Int(cm.rounded())) cm"
        case .imperial:
            let totalInches = Int((cm / 2.54).rounded())
            return "\(totalInches / 12) ft \(totalInches % 12) in"
        }
    }

    func waterText(ml: Double) -> String {
        switch self {
        case .metric:
            if ml >= 1000 { return "\((ml / 1000).formatted(.number.precision(.fractionLength(0...2)))) L" }
            return "\(Int(ml.rounded())) ml"
        case .imperial:
            return "\(Int((ml / 29.5735).rounded())) fl oz"
        }
    }

    var weightUnit: String { self == .metric ? "kg" : "lb" }
    func displayWeight(kg: Double) -> Double { self == .metric ? kg : kg * 2.20462 }
    func kilograms(fromDisplay value: Double) -> Double { self == .metric ? value : value / 2.20462 }
}

nonisolated struct UserProfile: Codable, Equatable, Sendable {
    var name: String = ""
    var age: Int = 30
    var sex: Sex = .female
    var heightCm: Double = 170
    var weightKg: Double = 70
    var targetWeightKg: Double = 65
    var activity: ActivityLevel = .light
    var goal: GoalType = .maintain
    /// kg per week the user wants to lose/gain.
    var weeklyRateKg: Double = 0.5
    var diet: DietPreset = .balanced
    var units: UnitSystem = .metric
    var hasOnboarded: Bool = false
    /// Set by the user or by an accepted adaptive suggestion; wins over the
    /// formula until cleared.
    var calorieOverride: Double?
    var waterGoalMl: Double?
    var syncToHealth: Bool = false
    var iCloudSync: Bool = false
}

nonisolated struct MacroGoals: Equatable, Sendable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

nonisolated enum NutritionGoals {
    /// Mifflin-St Jeor resting energy expenditure (kcal/day).
    static func bmr(sex: Sex, weightKg: Double, heightCm: Double, age: Int) -> Double {
        10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (sex == .male ? 5 : -161)
    }

    static func tdee(_ profile: UserProfile) -> Double {
        bmr(sex: profile.sex, weightKg: profile.weightKg, heightCm: profile.heightCm, age: profile.age) * profile.activity.multiplier
    }

    /// ~7700 kcal per kg of body weight.
    static let kcalPerKg = 7700.0

    /// Below these, unsupervised dieting stops being sensible.
    static func calorieFloor(for sex: Sex) -> Double { sex == .male ? 1500 : 1200 }

    static func calorieTarget(_ profile: UserProfile) -> Double {
        if let override = profile.calorieOverride, override > 0 { return override }
        let maintenance = tdee(profile)
        let dailyDelta = profile.weeklyRateKg * kcalPerKg / 7
        let target: Double
        switch profile.goal {
        case .maintain: target = maintenance
        case .lose: target = max(maintenance - dailyDelta, calorieFloor(for: profile.sex))
        case .gain: target = maintenance + dailyDelta
        }
        return (target / 10).rounded() * 10
    }

    static func macroGoals(calories: Double, diet: DietPreset) -> MacroGoals {
        let split = diet.split
        return MacroGoals(
            calories: calories,
            protein: (calories * split.protein / 4).rounded(),
            carbs: (calories * split.carbs / 4).rounded(),
            fat: (calories * split.fat / 9).rounded()
        )
    }

    static func macroGoals(_ profile: UserProfile) -> MacroGoals {
        macroGoals(calories: calorieTarget(profile), diet: profile.diet)
    }

    /// ~35 ml per kg, rounded to 50 ml.
    static func waterGoalMl(_ profile: UserProfile) -> Double {
        if let goal = profile.waterGoalMl, goal > 0 { return goal }
        return (profile.weightKg * 35 / 50).rounded() * 50
    }
}

/// UserDefaults-backed profile shared with the widget/watch through the App
/// Group suite.
@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore()
    private static let key = "nutrivision.profile.v1"

    private let defaults: UserDefaults

    var profile: UserProfile {
        didSet { save() }
    }

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            var testProfile = UserProfile()
            testProfile.hasOnboarded = true
            profile = testProfile
            return
        }
        if let data = defaults.data(forKey: Self.key), let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = decoded
        } else {
            // Carry over the pre-onboarding calorie goal if there was one.
            var fresh = UserProfile()
            let legacy = UserDefaults.standard.double(forKey: "nutrivision.calorieGoal")
            if legacy > 0 { fresh.calorieOverride = legacy }
            fresh.name = UserDefaults.standard.string(forKey: "nutrivision.userName") ?? ""
            profile = fresh
        }
    }

    var goals: MacroGoals { NutritionGoals.macroGoals(profile) }
    var waterGoalMl: Double { NutritionGoals.waterGoalMl(profile) }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: Self.key) }
    }
}
