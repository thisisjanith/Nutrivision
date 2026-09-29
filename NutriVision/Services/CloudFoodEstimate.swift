//
//  CloudFoodEstimate.swift
//  NutriVision
//
//  The structured answer the vision LLM returns for a captured frame, plus
//  the portion buckets and scaling helpers used to let the user correct it.
//

import Foundation

/// Discrete portion sizes the model chooses from. `relativeSize` is a rough
/// scale used only to rescale when the user picks a different bucket.
nonisolated enum PortionBucket: String, Codable, CaseIterable, Sendable {
    case tablespoon
    case palmSized = "palm-sized"
    case small
    case medium
    case cup
    case large

    var label: String {
        switch self {
        case .tablespoon: "Tablespoon"
        case .palmSized: "Palm-sized"
        case .small: "Small"
        case .medium: "Medium"
        case .cup: "Cup"
        case .large: "Large"
        }
    }

    var relativeSize: Double {
        switch self {
        case .tablespoon: 0.1
        case .palmSized: 0.5
        case .small: 0.7
        case .medium: 1.0
        case .cup: 1.0
        case .large: 1.5
        }
    }
}

nonisolated struct CloudFoodEstimate: Codable, Equatable, Sendable {
    struct Macros: Codable, Equatable, Sendable {
        var protein: Double
        var carbs: Double
        var fat: Double
    }

    var foodName: String
    var confidenceScore: Double
    var estimatedCalories: Double
    var macros: Macros
    /// True when the image suggests unseen calories, e.g. glossy oil or butter.
    var hiddenIngredientsFlag: Bool
    var hiddenIngredientsNote: String?
    var portion: PortionBucket?

    enum CodingKeys: String, CodingKey {
        case foodName = "food_name"
        case confidenceScore = "confidence_score"
        case estimatedCalories = "estimated_calories"
        case macros
        case hiddenIngredientsFlag = "hidden_ingredients_flag"
        case hiddenIngredientsNote = "hidden_ingredients_note"
        case portion
    }

    init(foodName: String, confidenceScore: Double, estimatedCalories: Double, macros: Macros,
         hiddenIngredientsFlag: Bool = false, hiddenIngredientsNote: String? = nil, portion: PortionBucket? = nil) {
        self.foodName = foodName
        self.confidenceScore = confidenceScore
        self.estimatedCalories = estimatedCalories
        self.macros = macros
        self.hiddenIngredientsFlag = hiddenIngredientsFlag
        self.hiddenIngredientsNote = hiddenIngredientsNote
        self.portion = portion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foodName = try c.decode(String.self, forKey: .foodName)
        confidenceScore = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .confidenceScore) ?? 0.5))
        estimatedCalories = try c.decode(Double.self, forKey: .estimatedCalories)
        macros = try c.decode(Macros.self, forKey: .macros)
        hiddenIngredientsFlag = try c.decodeIfPresent(Bool.self, forKey: .hiddenIngredientsFlag) ?? false
        hiddenIngredientsNote = try c.decodeIfPresent(String.self, forKey: .hiddenIngredientsNote)
        // An unknown bucket string shouldn't discard an otherwise good answer.
        portion = (try? c.decodeIfPresent(String.self, forKey: .portion)).flatMap {
            PortionBucket(rawValue: $0.lowercased())
        }
    }

    /// Accepts bare JSON or JSON wrapped in a markdown code fence, which chat
    /// models add even when told not to.
    static func decode(from data: Data) throws -> CloudFoodEstimate {
        let decoder = JSONDecoder()
        if let direct = try? decoder.decode(CloudFoodEstimate.self, from: data) { return direct }
        guard let text = String(data: data, encoding: .utf8),
              let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw VisionLLMError.malformedResponse
        }
        do {
            return try decoder.decode(CloudFoodEstimate.self, from: Data(text[start...end].utf8))
        } catch {
            throw VisionLLMError.malformedResponse
        }
    }

    var nutritionProfile: NutritionProfile {
        NutritionProfile(
            displayName: foodName,
            calories: estimatedCalories,
            proteinGrams: macros.protein,
            carbsGrams: macros.carbs,
            fatGrams: macros.fat,
            servingSize: portion.map { "\($0.label) portion" } ?? "1 serving"
        )
    }
}

extension NutritionProfile {
    /// Scales every quantity by `factor` — the slider override for a portion
    /// the model got wrong.
    nonisolated func scaled(by factor: Double) -> NutritionProfile {
        guard abs(factor - 1) > 0.001 else { return self }
        let text = factor.formatted(.number.precision(.fractionLength(0...2)))
        return NutritionProfile(
            displayName: displayName,
            calories: calories * factor,
            proteinGrams: proteinGrams * factor,
            carbsGrams: carbsGrams * factor,
            fatGrams: fatGrams * factor,
            servingSize: "\(servingSize) ×\(text)",
            fiberGrams: fiberGrams * factor,
            sugarGrams: sugarGrams * factor,
            sodiumMg: sodiumMg * factor,
            saturatedFatGrams: saturatedFatGrams * factor
        )
    }
}
