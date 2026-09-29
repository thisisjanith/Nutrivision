//
//  MealEntry.swift
//  NutriVision
//

import Foundation
import SwiftData

@Model
final class MealEntry {
    var id: UUID
    var name: String
    var timestamp: Date
    var calories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var confidenceScore: Double
    var servingSize: String

    init(name: String, calories: Double, protein: Double, carbs: Double,
         fat: Double, confidence: Double = 1.0, servingSize: String = "1 serving") {
        self.id = UUID()
        self.name = name
        self.timestamp = Date()
        self.calories = calories
        self.proteinGrams = protein
        self.carbsGrams = carbs
        self.fatGrams = fat
        self.confidenceScore = confidence
        self.servingSize = servingSize
    }
}

extension MealEntry {
    /// kcal recomputed from macro grams using the standard 4/4/9 formula.
    var macroCalories: Double {
        proteinGrams * 4 + carbsGrams * 4 + fatGrams * 9
    }

    var isLowConfidence: Bool {
        confidenceScore < 0.6
    }
}
