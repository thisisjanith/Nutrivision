//
//  TrackingModels.swift
//  NutriVision
//

import Foundation
import SwiftData

@Model
final class WeightEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var kilograms: Double = 0

    init(kilograms: Double, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.kilograms = kilograms
    }
}

@Model
final class WaterEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var milliliters: Double = 0

    init(milliliters: Double, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.milliliters = milliliters
    }
}

/// A favourite, custom food or recipe. Macros are per one `servingSize`.
@Model
final class SavedFood {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var calories: Double = 0
    var proteinGrams: Double = 0
    var carbsGrams: Double = 0
    var fatGrams: Double = 0
    var fiberGrams: Double = 0
    var sugarGrams: Double = 0
    var sodiumMg: Double = 0
    var saturatedFatGrams: Double = 0
    var servingSize: String = "1 serving"
    var isFavorite: Bool = false
    var isRecipe: Bool = false
    /// JSON `[RecipeIngredient]` for recipes.
    var ingredientsJSON: Data?

    init(name: String, calories: Double, protein: Double, carbs: Double, fat: Double,
         servingSize: String = "1 serving", isFavorite: Bool = false, isRecipe: Bool = false,
         fiber: Double = 0, sugar: Double = 0, sodiumMg: Double = 0, saturatedFat: Double = 0,
         ingredientsJSON: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.calories = calories
        self.proteinGrams = protein
        self.carbsGrams = carbs
        self.fatGrams = fat
        self.servingSize = servingSize
        self.isFavorite = isFavorite
        self.isRecipe = isRecipe
        self.fiberGrams = fiber
        self.sugarGrams = sugar
        self.sodiumMg = sodiumMg
        self.saturatedFatGrams = saturatedFat
        self.ingredientsJSON = ingredientsJSON
    }

    var nutritionProfile: NutritionProfile {
        NutritionProfile(displayName: name, calories: calories, proteinGrams: proteinGrams, carbsGrams: carbsGrams,
                         fatGrams: fatGrams, servingSize: servingSize, fiberGrams: fiberGrams, sugarGrams: sugarGrams,
                         sodiumMg: sodiumMg, saturatedFatGrams: saturatedFatGrams)
    }
}

nonisolated struct RecipeIngredient: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}
