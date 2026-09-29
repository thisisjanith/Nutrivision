//
//  FoodDatabase.swift
//  NutriVision
//
//  Bundled nutrition database (per-100 g values, USDA-style) with text search
//  and serving-unit conversion. Loaded once from `FoodDatabase.json`.
//

import Foundation

nonisolated struct ServingOption: Equatable, Identifiable, Sendable {
    var id: String { label }
    let label: String
    let grams: Double
}

nonisolated struct FoodRecord: Decodable, Identifiable, Equatable, Sendable {
    struct Serving: Decodable, Equatable, Sendable {
        let label: String
        let grams: Double
    }

    let name: String
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let sugar: Double
    let sodiumMg: Double
    let satFat: Double
    let servings: [Serving]
    let aliases: String

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, kcal, protein, carbs, fat, fiber, sugar, servings, aliases
        case sodiumMg = "sodium_mg"
        case satFat = "sat_fat"
    }

    /// Household servings from the database plus grams and ounces, so any
    /// food can be logged by weight.
    var servingOptions: [ServingOption] {
        servings.map { ServingOption(label: $0.label, grams: $0.grams) }
            + [ServingOption(label: "100 g", grams: 100), ServingOption(label: "1 oz", grams: 28.3495)]
    }

    /// Nutrition for `grams` of this food.
    func profile(grams: Double, servingLabel: String) -> NutritionProfile {
        let k = grams / 100
        return NutritionProfile(
            displayName: name, calories: kcal * k, proteinGrams: protein * k, carbsGrams: carbs * k,
            fatGrams: fat * k, servingSize: servingLabel, fiberGrams: fiber * k, sugarGrams: sugar * k,
            sodiumMg: sodiumMg * k, saturatedFatGrams: satFat * k
        )
    }

    var defaultProfile: NutritionProfile {
        let first = servingOptions[0]
        return profile(grams: first.grams, servingLabel: first.label)
    }
}

nonisolated final class FoodDatabase: @unchecked Sendable {
    static let shared = FoodDatabase()

    let foods: [FoodRecord]

    init(foods: [FoodRecord]? = nil) {
        if let foods {
            self.foods = foods
        } else if let url = Bundle.main.url(forResource: "FoodDatabase", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode([FoodRecord].self, from: data) {
            self.foods = decoded
        } else {
            self.foods = []
        }
    }

    /// Ranks foods against a free-text query: exact name > name prefix > word
    /// prefix > alias/substring. Every query word must match somewhere.
    func search(_ query: String, limit: Int = 30) -> [FoodRecord] {
        let words = query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty else { return [] }
        let normalizedQuery = words.joined(separator: " ")

        var scored: [(FoodRecord, Int)] = []
        for food in foods {
            let name = food.name.lowercased()
            let haystack = name + " " + food.aliases.lowercased()
            guard words.allSatisfy({ haystack.contains($0) }) else { continue }

            var score = 10
            if name == normalizedQuery { score = 100 }
            else if name.hasPrefix(normalizedQuery) { score = 80 }
            else if name.split(separator: " ").contains(where: { word in words.contains { word.hasPrefix($0) } }) { score = 50 }
            else if name.contains(words[0]) { score = 30 }
            scored.append((food, score - min(name.count, 9)))
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.name < $1.0.name }
            .prefix(limit).map(\.0)
    }

    func food(named name: String) -> FoodRecord? {
        foods.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
