//
//  USDAClient.swift
//  NutriVision
//
//  USDA FoodData Central lookup for branded products, used when Open Food
//  Facts has no entry (or no calorie data) for a barcode.
//

import Foundation

nonisolated struct USDAClient: ProductLookup {
    var session: URLSession = .shared
    /// `DEMO_KEY` works but is heavily rate-limited; set a real key in
    /// `AppConfig.usdaAPIKey` before shipping.
    var apiKey: String = AppConfig.usdaAPIKey

    func product(barcode: String) async throws -> NutritionProfile? {
        guard OpenFoodFactsClient.isPlausibleBarcode(barcode),
              let url = Self.url(for: barcode, apiKey: apiKey) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("NutriVision/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try Self.parse(data, barcode: barcode)
    }

    static func url(for barcode: String, apiKey: String) -> URL? {
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")
        components?.queryItems = [
            URLQueryItem(name: "query", value: barcode),
            URLQueryItem(name: "dataType", value: "Branded"),
            URLQueryItem(name: "pageSize", value: "5"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        return components?.url
    }

    /// FoodData Central nutrient numbers.
    private enum Nutrient {
        static let energyKcal = 1008
        static let protein = 1003
        static let fat = 1004
        static let carbs = 1005
    }

    static func parse(_ data: Data, barcode: String) throws -> NutritionProfile? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        // The search is free-text, so insist on an exact GTIN match — a near
        // hit would silently log the wrong product. GTINs lose leading zeros
        // in some records, hence the trimming.
        let wanted = barcode.trimmingLeadingZeros()
        guard let food = response.foods.first(where: { $0.gtinUpc?.trimmingLeadingZeros() == wanted }) else {
            return nil
        }

        var per100g: [Int: Double] = [:]
        for nutrient in food.foodNutrients {
            if let id = nutrient.nutrientId, let value = nutrient.value { per100g[id] = value }
        }
        guard let kcal = per100g[Nutrient.energyKcal], kcal > 0 else { return nil }

        // Branded values are per 100 g/ml; scale to the label serving when it
        // is expressed in a weight or volume we can convert.
        var factor = 1.0
        var serving = "100 g"
        if let size = food.servingSize, size > 0, let unit = food.servingSizeUnit?.lowercased(),
           ["g", "grm", "ml", "mlt"].contains(unit) {
            factor = size / 100
            let household = food.householdServingFullText?.trimmingCharacters(in: .whitespaces) ?? ""
            let amount = "\(Int(size.rounded())) \(unit.hasPrefix("m") ? "ml" : "g")"
            serving = household.isEmpty ? amount : "\(household) (\(amount))"
        }

        let name = (food.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return NutritionProfile(
            displayName: name.isEmpty ? "Packaged Food" : name.capitalized,
            calories: kcal * factor,
            proteinGrams: (per100g[Nutrient.protein] ?? 0) * factor,
            carbsGrams: (per100g[Nutrient.carbs] ?? 0) * factor,
            fatGrams: (per100g[Nutrient.fat] ?? 0) * factor,
            servingSize: serving
        )
    }

    private struct Response: Decodable {
        let foods: [Food]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            foods = (try? container.decode([Food].self, forKey: .foods)) ?? []
        }
        enum CodingKeys: String, CodingKey { case foods }
    }

    private struct Food: Decodable {
        let description: String?
        let gtinUpc: String?
        let servingSize: Double?
        let servingSizeUnit: String?
        let householdServingFullText: String?
        let foodNutrients: [FoodNutrient]
    }

    private struct FoodNutrient: Decodable {
        let nutrientId: Int?
        let value: Double?
    }
}

/// Tries each source in order. A source that throws is skipped so an outage at
/// one database doesn't hide a hit in the next; the error only surfaces if
/// nothing answered at all.
nonisolated struct FallbackProductLookup: ProductLookup {
    let sources: [any ProductLookup]

    func product(barcode: String) async throws -> NutritionProfile? {
        var lastError: Error?
        var anySourceAnswered = false
        for source in sources {
            do {
                if let profile = try await source.product(barcode: barcode) { return profile }
                anySourceAnswered = true
            } catch {
                lastError = error
            }
        }
        if !anySourceAnswered, let lastError { throw lastError }
        return nil
    }
}

private extension String {
    nonisolated func trimmingLeadingZeros() -> String {
        String(drop(while: { $0 == "0" }))
    }
}
