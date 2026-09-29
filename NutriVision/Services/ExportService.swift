//
//  ExportService.swift
//  NutriVision
//

import Foundation
import UIKit

nonisolated enum ExportService {
    static let csvHeader = "date,time,meal,name,serving,calories,protein_g,carbs_g,fat_g,fiber_g,sugar_g,sodium_mg,sat_fat_g"

    static func csvField(_ value: String) -> String {
        guard value.contains(where: { [",", "\"", "\n", "\r"].contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func csv(meals: [MealEntry], calendar: Calendar = .current) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        dateFormatter.timeZone = calendar.timeZone
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")

        func n(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US_POSIX")).grouping(.never)) }

        let rows = meals.sorted { $0.timestamp < $1.timestamp }.map { meal in
            [dateFormatter.string(from: meal.timestamp), timeFormatter.string(from: meal.timestamp), meal.mealType.title,
             csvField(meal.name), csvField(meal.servingSize), n(meal.calories), n(meal.proteinGrams), n(meal.carbsGrams),
             n(meal.fatGrams), n(meal.fiberGrams), n(meal.sugarGrams), n(meal.sodiumMg), n(meal.saturatedFatGrams)]
                .joined(separator: ",")
        }
        return ([csvHeader] + rows).joined(separator: "\n") + "\n"
    }

    static func writeCSV(meals: [MealEntry]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NutriVision-meals.csv")
        try csv(meals: meals).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// One-page-per-N-rows PDF: per-day totals with the meals beneath.
    static func pdf(meals: [MealEntry], title: String = "NutriVision Food Log", calendar: Calendar = .current) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 48
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22)]
        let dayAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13)]
        let rowAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11)]
        let mutedAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray]

        let byDay = Dictionary(grouping: meals) { calendar.startOfDay(for: $0.timestamp) }
        let days = byDay.keys.sorted(by: >)

        return renderer.pdfData { context in
            var y = margin
            func newPage() {
                context.beginPage()
                y = margin
            }
            func draw(_ text: String, _ attrs: [NSAttributedString.Key: Any], x: CGFloat = margin, height: CGFloat = 18) {
                if y + height > pageRect.height - margin { newPage() }
                (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
                y += height
            }
            newPage()
            draw(title, titleAttrs, height: 34)
            draw("Generated \(Date().formatted(date: .abbreviated, time: .shortened))", mutedAttrs, height: 26)
            if days.isEmpty { draw("No meals logged.", rowAttrs) }

            for day in days {
                let dayMeals = (byDay[day] ?? []).sorted { $0.timestamp < $1.timestamp }
                let kcal = dayMeals.reduce(0) { $0 + $1.calories }
                let p = dayMeals.reduce(0) { $0 + $1.proteinGrams }
                let c = dayMeals.reduce(0) { $0 + $1.carbsGrams }
                let f = dayMeals.reduce(0) { $0 + $1.fatGrams }
                y += 6
                draw("\(day.formatted(date: .complete, time: .omitted))  —  \(Int(kcal.rounded())) kcal  (P \(Int(p.rounded())) / C \(Int(c.rounded())) / F \(Int(f.rounded())) g)", dayAttrs, height: 20)
                for meal in dayMeals {
                    draw("\(meal.timestamp.formatted(date: .omitted, time: .shortened))  \(meal.mealType.title)  ·  \(meal.name) (\(meal.servingSize))", rowAttrs, x: margin + 8)
                    y -= 4
                    draw("\(Int(meal.calories.rounded())) kcal · P \(Int(meal.proteinGrams.rounded())) · C \(Int(meal.carbsGrams.rounded())) · F \(Int(meal.fatGrams.rounded()))", mutedAttrs, x: margin + 8, height: 18)
                }
            }
        }
    }

    static func writePDF(meals: [MealEntry]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NutriVision-food-log.pdf")
        try pdf(meals: meals).write(to: url, options: .atomic)
        return url
    }
}
