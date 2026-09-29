//
//  NutritionSource.swift
//  NutriVision
//

import Foundation
import UIKit

/// Maps a recognised label to nutrition. A protocol so the scanner pipeline
/// can be tested (and the backing data swapped) without touching the maps.
protocol NutritionSource: Sendable {
    func nutrition(forLabel label: String) -> NutritionProfile?
}

/// Classifier tables first (they match the model's raw labels), then the
/// bundled food database by name.
nonisolated struct LocalNutritionSource: NutritionSource {
    var database: FoodDatabase = .shared

    func nutrition(forLabel label: String) -> NutritionProfile? {
        if let mapped = FoodNutritionMap.lookup(label: label) { return mapped }
        let first = label.split(separator: ",").first.map(String.init) ?? label
        return database.search(first.replacingOccurrences(of: "_", with: " "), limit: 1).first?.defaultProfile
    }
}

/// Anything that can rank a still image; `ClassifierService` is the real one.
protocol FoodClassifying: Sendable {
    func classify(image: UIImage) async throws -> [ClassificationResult]
}

extension ClassifierService: FoodClassifying {}
