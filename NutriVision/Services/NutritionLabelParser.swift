//
//  NutritionLabelParser.swift
//  NutriVision
//
//  Turns the text Vision reads off a Nutrition Facts panel into a
//  `NutritionProfile`. Pure string processing so it can be unit-tested with
//  captured OCR output rather than needing a camera.
//

import Foundation

nonisolated enum NutritionLabelParser {
    /// Returns nil unless calories (or enough macros to derive them) were found.
    static func parse(lines: [String]) -> NutritionProfile? {
        // OCR splits "Calories" and "230" across lines unpredictably, so the
        // panel is flattened to one lowercase string and searched with
        // proximity-limited patterns.
        let text = lines.joined(separator: " ").lowercased()

        let protein = grams(after: "protein", in: text)
        let carbs = grams(after: "carbohydrate", in: text)
        let fat = totalFat(in: text)

        var calories = firstNumber(pattern: #"calories(?!\s*from)[^0-9]{0,12}(\d{1,4})"#, in: text)
            ?? firstNumber(pattern: #"(\d{2,4})\s*kcal"#, in: text)
        if calories == nil, protein != nil || carbs != nil || fat != nil {
            calories = (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9
        }
        guard let calories, calories > 0 else { return nil }

        return NutritionProfile(
            displayName: "Labelled Food",
            calories: calories,
            proteinGrams: protein ?? 0,
            carbsGrams: carbs ?? 0,
            fatGrams: fat ?? 0,
            servingSize: servingSize(in: lines) ?? "1 serving"
        )
    }

    private static func grams(after keyword: String, in text: String) -> Double? {
        firstNumber(pattern: "\(keyword)[a-z]*[^0-9]{0,12}(\\d+(?:\\.\\d+)?)\\s*g", in: text)
    }

    /// "Total Fat 8g" is the line we want; "Saturated Fat 1g" and "Trans Fat 0g"
    /// are sub-lines that would otherwise match a bare "fat" search.
    private static func totalFat(in text: String) -> Double? {
        if let total = firstNumber(pattern: #"total\s*fat[^0-9]{0,12}(\d+(?:\.\d+)?)\s*g"#, in: text) {
            return total
        }
        guard let regex = try? NSRegularExpression(pattern: #"fat[^0-9]{0,12}(\d+(?:\.\d+)?)\s*g"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            let start = text.index(text.startIndex, offsetBy: max(0, match.range.location - 12))
            let end = text.index(text.startIndex, offsetBy: match.range.location)
            let prefix = text[start..<end]
            if ["saturated", "trans", "poly", "mono", "unsat"].contains(where: prefix.contains) { continue }
            if let r = Range(match.range(at: 1), in: text) { return Double(text[r]) }
        }
        return nil
    }

    private static func servingSize(in lines: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard let range = lower.range(of: "serving size") else { continue }
            var rest = line[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: ": ").union(.whitespaces))
            if rest.isEmpty, index + 1 < lines.count { rest = lines[index + 1].trimmingCharacters(in: .whitespaces) }
            return rest.isEmpty ? nil : String(rest.prefix(32))
        }
        return nil
    }

    private static func firstNumber(pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }
}
