//
//  MealEntry.swift
//  NutriVision
//

import Foundation
import SwiftData

/// Every stored property has a default so SwiftData can lightweight-migrate
/// existing stores when fields are added, and so the model stays valid for
/// CloudKit sync (which requires defaults and forbids unique constraints).
@Model
final class MealEntry {
    var id: UUID = UUID()
    var name: String = ""
    var timestamp: Date = Date()
    var calories: Double = 0
    var proteinGrams: Double = 0
    var carbsGrams: Double = 0
    var fatGrams: Double = 0
    var confidenceScore: Double = 1.0
    var servingSize: String = "1 serving"
    var mealTypeRaw: String = MealType.snack.rawValue
    var fiberGrams: Double = 0
    var sugarGrams: Double = 0
    var sodiumMg: Double = 0
    var saturatedFatGrams: Double = 0
    /// Thumbnail JPEG of the scanned meal, kept out of the main store file.
    @Attribute(.externalStorage) var photoData: Data?

    init(name: String, calories: Double, protein: Double, carbs: Double,
         fat: Double, confidence: Double = 1.0, servingSize: String = "1 serving",
         mealType: MealType = .suggested(), timestamp: Date = Date(),
         fiber: Double = 0, sugar: Double = 0, sodiumMg: Double = 0,
         saturatedFat: Double = 0, photoData: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.timestamp = timestamp
        self.calories = calories
        self.proteinGrams = protein
        self.carbsGrams = carbs
        self.fatGrams = fat
        self.confidenceScore = confidence
        self.servingSize = servingSize
        self.mealTypeRaw = mealType.rawValue
        self.fiberGrams = fiber
        self.sugarGrams = sugar
        self.sodiumMg = sodiumMg
        self.saturatedFatGrams = saturatedFat
        self.photoData = photoData
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

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }
}
