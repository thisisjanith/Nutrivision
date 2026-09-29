//
//  OpenFoodFactsClient.swift
//  NutriVision
//
//  Looks up packaged products by barcode in the Open Food Facts database and
//  reduces the response to the same `NutritionProfile` the classifier path
//  produces, so a barcode scan flows through the app exactly like a photo scan.
//

import Foundation

/// Abstraction over the product database so the scanner can be tested without
/// touching the network.
protocol ProductLookup: Sendable {
    /// Returns nil when the barcode isn't in the database or the entry has no
    /// usable calorie data. Throws only for transport / decoding failures.
    func product(barcode: String) async throws -> NutritionProfile?
}

nonisolated struct OpenFoodFactsClient: ProductLookup {
    var session: URLSession = .shared

    func product(barcode: String) async throws -> NutritionProfile? {
        guard Self.isPlausibleBarcode(barcode),
              let url = Self.url(for: barcode) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 10)
        // Open Food Facts asks API clients to identify themselves.
        request.setValue("NutriVision/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        // A 404 is how the API says "unknown barcode" on some paths.
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }

        return try Self.parse(data)
    }

    static func isPlausibleBarcode(_ code: String) -> Bool {
        (6...14).contains(code.count) && code.allSatisfy(\.isASCII) && code.allSatisfy(\.isNumber)
    }

    static func url(for barcode: String) -> URL? {
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")
        components?.queryItems = [
            URLQueryItem(name: "fields", value: "product_name,serving_size,nutriments")
        ]
        return components?.url
    }

    // MARK: - Parsing

    static func parse(_ data: Data) throws -> NutritionProfile? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.status != 0, let product = response.product else { return nil }

        // Prefer per-serving values (what a person actually eats); fall back
        // to per-100g when the label only lists that.
        let perServing = product.nutriments.calories(suffix: "serving") != nil
        let suffix = perServing ? "serving" : "100g"
        guard let calories = product.nutriments.calories(suffix: suffix), calories > 0 else { return nil }

        let name = product.productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let servingSize = product.servingSize?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return NutritionProfile(
            displayName: name.isEmpty ? "Packaged Food" : name,
            calories: calories,
            proteinGrams: product.nutriments.value("proteins_\(suffix)") ?? 0,
            carbsGrams: product.nutriments.value("carbohydrates_\(suffix)") ?? 0,
            fatGrams: product.nutriments.value("fat_\(suffix)") ?? 0,
            servingSize: perServing ? (servingSize.isEmpty ? "1 serving" : servingSize) : "100 g"
        )
    }

    private struct Response: Decodable {
        let status: Int?
        let product: Product?
    }

    private struct Product: Decodable {
        let productName: String?
        let servingSize: String?
        let nutriments: Nutriments

        enum CodingKeys: String, CodingKey {
            case productName = "product_name"
            case servingSize = "serving_size"
            case nutriments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            productName = try? container.decodeIfPresent(String.self, forKey: .productName)
            servingSize = try? container.decodeIfPresent(String.self, forKey: .servingSize)
            nutriments = (try? container.decodeIfPresent(Nutriments.self, forKey: .nutriments)) ?? Nutriments(values: [:])
        }
    }

    /// Nutriment values arrive as numbers *or* numeric strings depending on
    /// how the entry was contributed, so each is decoded leniently and
    /// anything unparseable is dropped rather than failing the whole product.
    private struct Nutriments: Decodable {
        let values: [String: Double]

        init(values: [String: Double]) { self.values = values }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode([String: LossyDouble].self)
            values = raw.compactMapValues(\.value)
        }

        func value(_ key: String) -> Double? { values[key] }

        /// kcal for the given basis; falls back to converting kJ when only
        /// `energy_*` (which Open Food Facts stores in kJ) is present.
        func calories(suffix: String) -> Double? {
            if let kcal = values["energy-kcal_\(suffix)"] { return kcal }
            if let kilojoules = values["energy_\(suffix)"] { return kilojoules / 4.184 }
            return nil
        }
    }

    private struct LossyDouble: Decodable {
        let value: Double?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) {
                value = number
            } else if let string = try? container.decode(String.self) {
                value = Double(string)
            } else {
                value = nil
            }
        }
    }
}
