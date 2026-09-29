//
//  AppShortcuts.swift
//  NutriVision
//
//  App-only intents (they need the SwiftData store) and the shortcut phrases.
//

import AppIntents
import SwiftData

struct LogFoodIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Food"
    static let description = IntentDescription("Logs a food from the NutriVision database, e.g. \"a banana\".")

    @Parameter(title: "Food", requestValueDialog: "What did you eat?")
    var food: String

    @Parameter(title: "Servings", default: 1)
    var servings: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let match = FoodDatabase.shared.search(food, limit: 1).first else {
            return .result(dialog: "I couldn't find \"\(food)\" in the food database.")
        }
        let profile = match.defaultProfile.scaled(by: max(servings, 0.1))
        let context = PersistenceController.shared.mainContext
        let meal = MealEntry(
            name: match.name, calories: profile.calories, protein: profile.proteinGrams, carbs: profile.carbsGrams,
            fat: profile.fatGrams, servingSize: profile.servingSize, fiber: profile.fiberGrams, sugar: profile.sugarGrams,
            sodiumMg: profile.sodiumMg, saturatedFat: profile.saturatedFatGrams
        )
        context.insert(meal)
        Tracker.shared.mealSaved(meal, context: context)
        let remaining = Int(DailySnapshot.load().caloriesRemaining.rounded())
        return .result(dialog: "Logged \(match.name), \(Int(profile.calories.rounded())) calories. \(remaining) left today.")
    }
}

struct NutriVisionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogFoodIntent(), phrases: ["Log food in \(.applicationName)", "Log a meal in \(.applicationName)"],
                    shortTitle: "Log Food", systemImageName: "fork.knife")
        AppShortcut(intent: CaloriesLeftIntent(), phrases: ["How many calories are left in \(.applicationName)", "Calories left in \(.applicationName)"],
                    shortTitle: "Calories Left", systemImageName: "flame.fill")
        AppShortcut(intent: OpenScannerIntent(), phrases: ["Scan food with \(.applicationName)"],
                    shortTitle: "Scan Food", systemImageName: "camera.viewfinder")
        AppShortcut(intent: AddWaterIntent(), phrases: ["Log water in \(.applicationName)"],
                    shortTitle: "Add Water", systemImageName: "drop.fill")
    }
}
