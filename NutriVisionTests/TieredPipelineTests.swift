//
//  TieredPipelineTests.swift
//  NutriVisionTests
//

import XCTest
import SwiftData
import UIKit
import Vision
@testable import NutriVision

final class NutritionLabelParserTests: XCTestCase {
    func testParsesTypicalFactsPanel() {
        let profile = NutritionLabelParser.parse(lines: [
            "Nutrition Facts", "Serving size 2/3 cup (55g)", "Calories", "230",
            "Total Fat 8g", "Saturated Fat 1g", "Trans Fat 0g",
            "Total Carbohydrate 37g", "Dietary Fiber 4g", "Protein 3g",
        ])
        XCTAssertEqual(profile?.calories, 230)
        XCTAssertEqual(profile?.fatGrams, 8)
        XCTAssertEqual(profile?.carbsGrams, 37)
        XCTAssertEqual(profile?.proteinGrams, 3)
        XCTAssertEqual(profile?.servingSize, "2/3 cup (55g)")
    }

    func testIgnoresCaloriesFromFatAndSaturatedFat() {
        let profile = NutritionLabelParser.parse(lines: ["Calories from fat 40", "Calories 120", "Saturated Fat 2g", "Fat 5g"])
        XCTAssertEqual(profile?.calories, 120)
        XCTAssertEqual(profile?.fatGrams, 5)
    }

    func testDerivesCaloriesFromMacrosWhenMissing() {
        let profile = NutritionLabelParser.parse(lines: ["Protein 10g", "Total Carbohydrate 20g", "Total Fat 5g"])
        let expected: Double = 40 + 80 + 45
        XCTAssertEqual(profile?.calories, expected)
    }

    func testReturnsNilForUnrelatedText() {
        XCTAssertNil(NutritionLabelParser.parse(lines: ["Best before 12/2027", "Keep refrigerated"]))
    }
}

final class CloudEstimateTests: XCTestCase {
    private let json = """
    {"food_name":"Oatmeal","confidence_score":0.82,"estimated_calories":300,
     "macros":{"protein":10,"carbs":54,"fat":6},"hidden_ingredients_flag":true,
     "hidden_ingredients_note":"Looks buttery","portion":"Medium"}
    """

    func testDecodesSchema() throws {
        let estimate = try CloudFoodEstimate.decode(from: Data(json.utf8))
        XCTAssertEqual(estimate.foodName, "Oatmeal")
        XCTAssertEqual(estimate.portion, .medium)
        XCTAssertTrue(estimate.hiddenIngredientsFlag)
        XCTAssertEqual(estimate.nutritionProfile.calories, 300)
    }

    func testDecodesJSONInsideCodeFence() throws {
        let estimate = try CloudFoodEstimate.decode(from: Data("```json\n\(json)\n```".utf8))
        XCTAssertEqual(estimate.foodName, "Oatmeal")
    }

    func testUnknownPortionDoesNotFailDecoding() throws {
        let estimate = try CloudFoodEstimate.decode(from: Data(json.replacingOccurrences(of: "Medium", with: "gigantic").utf8))
        XCTAssertNil(estimate.portion)
    }

    func testGarbageThrowsMalformed() {
        XCTAssertThrowsError(try CloudFoodEstimate.decode(from: Data("nope".utf8))) {
            XCTAssertEqual($0 as? VisionLLMError, .malformedResponse)
        }
    }

    func testPortionScalingScalesEveryMacro() {
        let base = NutritionProfile(displayName: "X", calories: 200, proteinGrams: 10, carbsGrams: 20, fatGrams: 4, servingSize: "1 bowl")
        let scaled = base.scaled(by: 1.5)
        XCTAssertEqual(scaled.calories, 300)
        XCTAssertEqual(scaled.proteinGrams, 15)
        XCTAssertEqual(scaled.servingSize, "1 bowl ×1.5")
        XCTAssertEqual(base.scaled(by: 1), base)
    }
}

final class USDAParsingTests: XCTestCase {
    func testScalesPer100gToLabelServing() throws {
        let json = """
        {"foods":[{"description":"GRANOLA BAR","gtinUpc":"012345678905","servingSize":40,"servingSizeUnit":"g",
         "householdServingFullText":"1 bar","foodNutrients":[{"nutrientId":1008,"value":450},{"nutrientId":1003,"value":10},
         {"nutrientId":1005,"value":65},{"nutrientId":1004,"value":15}]}]}
        """
        let profile = try USDAClient.parse(Data(json.utf8), barcode: "12345678905")
        XCTAssertEqual(profile?.calories ?? 0, 180, accuracy: 0.001)
        XCTAssertEqual(profile?.servingSize, "1 bar (40 g)")
    }

    func testRejectsNonMatchingGTIN() throws {
        let json = #"{"foods":[{"description":"Other","gtinUpc":"999999999999","foodNutrients":[{"nutrientId":1008,"value":100}]}]}"#
        XCTAssertNil(try USDAClient.parse(Data(json.utf8), barcode: "012345678905"))
    }
}

final class FallbackLookupTests: XCTestCase {
    private struct Stub: ProductLookup {
        var result: NutritionProfile?
        var fails = false
        func product(barcode: String) async throws -> NutritionProfile? {
            if fails { throw URLError(.notConnectedToInternet) }
            return result
        }
    }
    private let profile = NutritionProfile(displayName: "P", calories: 1, proteinGrams: 0, carbsGrams: 0, fatGrams: 0, servingSize: "1")

    func testFallsThroughMissToSecondSource() async throws {
        let lookup = FallbackProductLookup(sources: [Stub(result: nil), Stub(result: profile)])
        let found = try await lookup.product(barcode: "123456")
        XCTAssertEqual(found, profile)
    }

    func testSkipsFailingSource() async throws {
        let lookup = FallbackProductLookup(sources: [Stub(fails: true), Stub(result: profile)])
        let found = try await lookup.product(barcode: "123456")
        XCTAssertEqual(found, profile)
    }

    func testThrowsOnlyWhenNoSourceAnswered() async {
        let lookup = FallbackProductLookup(sources: [Stub(fails: true), Stub(fails: true)])
        do { _ = try await lookup.product(barcode: "123456"); XCTFail("expected throw") } catch {}
    }

    func testMissIsNotAnErrorWhenOneSourceAnswered() async throws {
        let lookup = FallbackProductLookup(sources: [Stub(result: nil), Stub(fails: true)])
        let found = try await lookup.product(barcode: "123456")
        XCTAssertNil(found)
    }
}

final class FoodRegionTests: XCTestCase {
    func testVisionBoxFlipsToTopLeftOrigin() {
        let region = FoodRegion.fromVision(CGRect(x: 0.1, y: 0.6, width: 0.2, height: 0.3), kind: .food, confidence: 1)
        XCTAssertEqual(region.box.minY, 0.1, accuracy: 0.0001)
    }

    func testViewRectAccountsForAspectFillCrop() {
        // Landscape image in a square view: width is cropped, height fits.
        let region = FoodRegion(box: CGRect(x: 0, y: 0, width: 1, height: 1), kind: .food, confidence: 1)
        let rect = region.viewRect(in: CGSize(width: 100, height: 100), imageSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(rect.width, 200, accuracy: 0.001)
        XCTAssertEqual(rect.minX, -50, accuracy: 0.001)
    }

    func testSmootherConvergesTowardTarget() {
        var smoother = BoxSmoother(alpha: 0.5)
        _ = smoother.update(CGRect(x: 0, y: 0, width: 1, height: 1))
        let next = smoother.update(CGRect(x: 1, y: 0, width: 1, height: 1))
        XCTAssertEqual(next.minX, 0.5, accuracy: 0.0001)
    }
}

@MainActor
final class EstimateCacheTests: XCTestCase {
    private func image(_ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format)
        return renderer.image { context in draw(context.cgContext) }
    }

    func testHitsForSameImageAndMissesForDifferentOne() throws {
        let container = try ModelContainer(for: CachedEstimate.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let cache = EstimateCache(context: ModelContext(container))
        let plate = image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor.orange.setFill(); ctx.fillEllipse(in: CGRect(x: 40, y: 40, width: 176, height: 176))
        }
        let stripes = image { ctx in
            for i in 0..<8 {
                (i % 2 == 0 ? UIColor.blue : UIColor.green).setFill()
                ctx.fill(CGRect(x: i * 32, y: 0, width: 32, height: 256))
            }
        }
        let estimate = CloudFoodEstimate(foodName: "Orange plate", confidenceScore: 0.9, estimatedCalories: 100,
                                         macros: .init(protein: 1, carbs: 20, fat: 1))
        XCTAssertNil(cache.lookup(image: plate))
        cache.store(estimate, image: plate)
        XCTAssertEqual(cache.lookup(image: plate)?.foodName, "Orange plate")
        #if !targetEnvironment(simulator)
        // The simulator's CPU-only feature print barely separates images
        // (measured 0.002 between very different ones), so the miss case is
        // only meaningful on hardware.
        XCTAssertNil(cache.lookup(image: stripes))
        #endif
    }
}
