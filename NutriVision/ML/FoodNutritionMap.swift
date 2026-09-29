//
//  FoodNutritionMap.swift
//  NutriVision
//
//  MobileNetV2 (trained on ImageNet) returns raw synset class labels, not
//  nutrition data. This table maps the food-relevant subset of those labels
//  to approximate calorie/macro profiles for a typical single serving, plus
//  a friendlier display name and serving-size string used in the UI.
//

import Foundation

struct NutritionProfile: Sendable, Equatable {
    let displayName: String
    let calories: Double
    let proteinGrams: Double
    let carbsGrams: Double
    let fatGrams: Double
    let servingSize: String
}

/// Minimum classifier confidence required before a result is treated as a
/// confident auto-fill. Below this, the UI should flag the detection as
/// low-confidence rather than silently accepting it.
let lowConfidenceThreshold: Float = 0.6

enum FoodNutritionMap {
    /// Keyed by the raw ImageNet/MobileNetV2 class label (lowercased).
    static let profiles: [String: NutritionProfile] = [
        "granny smith": NutritionProfile(displayName: "Apple", calories: 95, proteinGrams: 0.5, carbsGrams: 25, fatGrams: 0.3, servingSize: "1 medium"),
        "banana": NutritionProfile(displayName: "Banana", calories: 105, proteinGrams: 1.3, carbsGrams: 27, fatGrams: 0.4, servingSize: "1 medium"),
        "orange": NutritionProfile(displayName: "Orange", calories: 62, proteinGrams: 1.2, carbsGrams: 15, fatGrams: 0.2, servingSize: "1 medium"),
        "lemon": NutritionProfile(displayName: "Lemon", calories: 17, proteinGrams: 0.6, carbsGrams: 5, fatGrams: 0.2, servingSize: "1 medium"),
        "fig": NutritionProfile(displayName: "Fig", calories: 37, proteinGrams: 0.4, carbsGrams: 10, fatGrams: 0.1, servingSize: "1 medium"),
        "pomegranate": NutritionProfile(displayName: "Pomegranate", calories: 105, proteinGrams: 2.1, carbsGrams: 26, fatGrams: 1.5, servingSize: "1/2 cup arils"),
        "strawberry": NutritionProfile(displayName: "Strawberries", calories: 49, proteinGrams: 1.0, carbsGrams: 12, fatGrams: 0.5, servingSize: "1 cup"),
        "pineapple": NutritionProfile(displayName: "Pineapple", calories: 82, proteinGrams: 0.9, carbsGrams: 22, fatGrams: 0.2, servingSize: "1 cup"),
        "custard apple": NutritionProfile(displayName: "Custard Apple", calories: 101, proteinGrams: 1.7, carbsGrams: 25, fatGrams: 0.5, servingSize: "1/2 fruit"),

        "corn": NutritionProfile(displayName: "Corn", calories: 96, proteinGrams: 3.4, carbsGrams: 21, fatGrams: 1.5, servingSize: "1 ear"),
        "cucumber": NutritionProfile(displayName: "Cucumber", calories: 16, proteinGrams: 0.7, carbsGrams: 4, fatGrams: 0.1, servingSize: "1 cup sliced"),
        "artichoke": NutritionProfile(displayName: "Artichoke", calories: 60, proteinGrams: 4.2, carbsGrams: 13, fatGrams: 0.2, servingSize: "1 medium"),
        "bell pepper": NutritionProfile(displayName: "Bell Pepper", calories: 24, proteinGrams: 1.0, carbsGrams: 6, fatGrams: 0.2, servingSize: "1 medium"),
        "head cabbage": NutritionProfile(displayName: "Cabbage", calories: 22, proteinGrams: 1.1, carbsGrams: 5, fatGrams: 0.1, servingSize: "1 cup"),
        "broccoli": NutritionProfile(displayName: "Broccoli", calories: 31, proteinGrams: 2.6, carbsGrams: 6, fatGrams: 0.3, servingSize: "1 cup"),
        "cauliflower": NutritionProfile(displayName: "Cauliflower", calories: 27, proteinGrams: 2.1, carbsGrams: 5, fatGrams: 0.3, servingSize: "1 cup"),
        "zucchini": NutritionProfile(displayName: "Zucchini", calories: 20, proteinGrams: 1.5, carbsGrams: 4, fatGrams: 0.4, servingSize: "1 cup sliced"),
        "acorn squash": NutritionProfile(displayName: "Acorn Squash", calories: 56, proteinGrams: 1.1, carbsGrams: 15, fatGrams: 0.1, servingSize: "1/2 cup"),
        "butternut squash": NutritionProfile(displayName: "Butternut Squash", calories: 63, proteinGrams: 1.4, carbsGrams: 16, fatGrams: 0.1, servingSize: "1 cup"),
        "spaghetti squash": NutritionProfile(displayName: "Spaghetti Squash", calories: 42, proteinGrams: 1.0, carbsGrams: 10, fatGrams: 0.4, servingSize: "1 cup"),
        "mushroom": NutritionProfile(displayName: "Mushrooms", calories: 15, proteinGrams: 2.2, carbsGrams: 2, fatGrams: 0.2, servingSize: "1 cup"),

        "pretzel": NutritionProfile(displayName: "Pretzel", calories: 108, proteinGrams: 3.0, carbsGrams: 22, fatGrams: 1.0, servingSize: "1 medium"),
        "bagel": NutritionProfile(displayName: "Bagel", calories: 245, proteinGrams: 10, carbsGrams: 48, fatGrams: 1.5, servingSize: "1 bagel"),
        "french loaf": NutritionProfile(displayName: "French Bread", calories: 140, proteinGrams: 5, carbsGrams: 27, fatGrams: 1.2, servingSize: "1 slice"),

        "cheeseburger": NutritionProfile(displayName: "Cheeseburger", calories: 535, proteinGrams: 27, carbsGrams: 40, fatGrams: 28, servingSize: "1 burger"),
        "hotdog": NutritionProfile(displayName: "Hot Dog", calories: 290, proteinGrams: 10, carbsGrams: 22, fatGrams: 18, servingSize: "1 hot dog"),
        "pizza": NutritionProfile(displayName: "Pizza", calories: 285, proteinGrams: 12, carbsGrams: 36, fatGrams: 10, servingSize: "1 slice"),
        "burrito": NutritionProfile(displayName: "Burrito", calories: 410, proteinGrams: 17, carbsGrams: 52, fatGrams: 15, servingSize: "1 burrito"),
        "guacamole": NutritionProfile(displayName: "Guacamole", calories: 150, proteinGrams: 2, carbsGrams: 9, fatGrams: 13, servingSize: "1/2 cup"),
        "carbonara": NutritionProfile(displayName: "Carbonara", calories: 520, proteinGrams: 20, carbsGrams: 55, fatGrams: 24, servingSize: "1 bowl"),
        "hot pot": NutritionProfile(displayName: "Hot Pot", calories: 400, proteinGrams: 28, carbsGrams: 20, fatGrams: 22, servingSize: "1 bowl"),
        "consomme": NutritionProfile(displayName: "Soup", calories: 90, proteinGrams: 6, carbsGrams: 8, fatGrams: 3, servingSize: "1 bowl"),
        "potpie": NutritionProfile(displayName: "Pot Pie", calories: 480, proteinGrams: 15, carbsGrams: 42, fatGrams: 28, servingSize: "1 pie"),

        "ice cream": NutritionProfile(displayName: "Ice Cream", calories: 210, proteinGrams: 3.5, carbsGrams: 24, fatGrams: 11, servingSize: "1 cup"),
        "ice lolly": NutritionProfile(displayName: "Ice Pop", calories: 60, proteinGrams: 0, carbsGrams: 15, fatGrams: 0, servingSize: "1 pop"),
        "trifle": NutritionProfile(displayName: "Trifle", calories: 330, proteinGrams: 5, carbsGrams: 45, fatGrams: 14, servingSize: "1 serving"),
        "chocolate sauce": NutritionProfile(displayName: "Chocolate Sauce", calories: 130, proteinGrams: 1, carbsGrams: 24, fatGrams: 4, servingSize: "2 tbsp"),

        "salad": NutritionProfile(displayName: "Salad", calories: 220, proteinGrams: 8, carbsGrams: 12, fatGrams: 16, servingSize: "1 bowl"),
        "sandwich": NutritionProfile(displayName: "Sandwich", calories: 350, proteinGrams: 18, carbsGrams: 35, fatGrams: 14, servingSize: "1 sandwich"),
    ]

    /// Keys ordered longest-first (ties broken alphabetically) so matching is
    /// deterministic and the most specific key wins — "hot dog" before "dog",
    /// "butternut squash" before "squash". The previous implementation walked
    /// the dictionary directly, whose order is unspecified and varies between
    /// launches, so an ambiguous label could map to a different food each run.
    private static let keysBySpecificity: [String] = profiles.keys.sorted {
        $0.count != $1.count ? $0.count > $1.count : $0 < $1
    }

    /// Looks up a nutrition profile for a raw classifier label.
    ///
    /// ImageNet labels are comma-separated synonym lists ("hotdog, hot dog,
    /// red hot"), so each synonym is tried on its own. Exact matches win
    /// outright; failing that we look for the key as a whole word sequence,
    /// which keeps "corn" from claiming "corn dog".
    static func lookup(label: String) -> NutritionProfile? {
        let synonyms = label
            .lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for synonym in synonyms {
            if let exact = profiles[synonym] { return exact }
        }

        for key in keysBySpecificity {
            for synonym in synonyms where synonym.containsWordSequence(key) {
                return profiles[key]
            }
        }

        return nil
    }
}

extension String {
    /// Splits into lowercased alphanumeric word tokens.
    fileprivate var wordTokens: [String] {
        lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    /// True when `phrase`'s words appear as a contiguous run of whole words.
    fileprivate func containsWordSequence(_ phrase: String) -> Bool {
        let haystack = wordTokens
        let needle = phrase.wordTokens
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }

    /// Turns a raw classifier label into something showable — first synonym
    /// only, title-cased. Used when a label has no nutrition mapping yet.
    var prettifiedClassLabel: String {
        let first = split(separator: ",").first.map(String.init) ?? self
        return first
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
