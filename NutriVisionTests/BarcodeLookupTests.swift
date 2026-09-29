//
//  BarcodeLookupTests.swift
//  NutriVisionTests
//

import XCTest
@testable import NutriVision

final class OpenFoodFactsParsingTests: XCTestCase {
    private func parse(_ json: String) throws -> NutritionProfile? {
        try OpenFoodFactsClient.parse(Data(json.utf8))
    }

    func testPrefersPerServingValues() throws {
        let profile = try parse("""
        {"status":1,"product":{"product_name":"Granola Bar","serving_size":"1 bar (40 g)",
         "nutriments":{"energy-kcal_serving":180,"proteins_serving":4,"carbohydrates_serving":26,"fat_serving":7,
                       "energy-kcal_100g":450,"proteins_100g":10,"carbohydrates_100g":65,"fat_100g":17.5}}}
        """)
        XCTAssertEqual(profile?.displayName, "Granola Bar")
        XCTAssertEqual(profile?.calories, 180)
        XCTAssertEqual(profile?.proteinGrams, 4)
        XCTAssertEqual(profile?.carbsGrams, 26)
        XCTAssertEqual(profile?.fatGrams, 7)
        XCTAssertEqual(profile?.servingSize, "1 bar (40 g)")
    }

    func testFallsBackToPer100g() throws {
        let profile = try parse("""
        {"status":1,"product":{"product_name":"Oats",
         "nutriments":{"energy-kcal_100g":370,"proteins_100g":13,"carbohydrates_100g":60,"fat_100g":7}}}
        """)
        XCTAssertEqual(profile?.calories, 370)
        XCTAssertEqual(profile?.servingSize, "100 g")
    }

    func testAcceptsNumbersEncodedAsStrings() throws {
        let profile = try parse("""
        {"status":1,"product":{"product_name":"Juice",
         "nutriments":{"energy-kcal_100g":"45.5","proteins_100g":"0.5","carbohydrates_100g":"10","fat_100g":""}}}
        """)
        XCTAssertEqual(profile?.calories, 45.5)
        XCTAssertEqual(profile?.proteinGrams, 0.5)
        XCTAssertEqual(profile?.fatGrams, 0, "an unparseable value should default to 0, not fail the product")
    }

    func testConvertsKilojoulesWhenKcalMissing() throws {
        let profile = try parse("""
        {"status":1,"product":{"product_name":"Crackers","nutriments":{"energy_100g":1674}}}
        """)
        XCTAssertEqual(try XCTUnwrap(profile?.calories), 400, accuracy: 0.5)
    }

    func testUnknownProductReturnsNil() throws {
        XCTAssertNil(try parse(#"{"status":0,"status_verbose":"product not found"}"#))
    }

    func testProductWithoutCaloriesReturnsNil() throws {
        XCTAssertNil(try parse(#"{"status":1,"product":{"product_name":"Mystery","nutriments":{}}}"#))
    }

    func testMissingNameGetsPlaceholder() throws {
        let profile = try parse(#"{"status":1,"product":{"nutriments":{"energy-kcal_100g":100}}}"#)
        XCTAssertEqual(profile?.displayName, "Packaged Food")
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try parse("not json"))
    }

    func testBarcodeValidation() {
        XCTAssertTrue(OpenFoodFactsClient.isPlausibleBarcode("5449000000996"))
        XCTAssertFalse(OpenFoodFactsClient.isPlausibleBarcode("12345"))
        XCTAssertFalse(OpenFoodFactsClient.isPlausibleBarcode("abc123456789"))
        XCTAssertFalse(OpenFoodFactsClient.isPlausibleBarcode("../../etc/passwd"))
    }
}

@MainActor
final class ScannerBarcodeFlowTests: XCTestCase {
    private struct MockLookup: ProductLookup {
        var result: Result<NutritionProfile?, Error>
        func product(barcode: String) async throws -> NutritionProfile? { try result.get() }
    }

    private let cola = NutritionProfile(
        displayName: "Cola", calories: 139, proteinGrams: 0, carbsGrams: 35, fatGrams: 0, servingSize: "330 ml"
    )

    func testKnownBarcodePublishesExactDetection() async {
        let viewModel = ScannerViewModel(productLookup: MockLookup(result: .success(cola)))
        await viewModel.handleBarcode("5449000000996")

        XCTAssertEqual(viewModel.detection?.displayName, "Cola")
        XCTAssertEqual(viewModel.detection?.isBarcodeScan, true)
        XCTAssertEqual(viewModel.detection?.confidence, 1.0)
        XCTAssertNil(viewModel.barcodeMessage)
        XCTAssertFalse(viewModel.isLookingUpBarcode)
    }

    func testBarcodeDetectionFeedsMealDraft() async throws {
        let viewModel = ScannerViewModel(productLookup: MockLookup(result: .success(cola)))
        await viewModel.handleBarcode("5449000000996")
        let draft = DraftMeal.from(detection: try XCTUnwrap(viewModel.detection))
        XCTAssertEqual(draft.name, "Cola")
        XCTAssertEqual(draft.carbsGrams, 35)
        XCTAssertEqual(draft.unitLabel, "330 ml")
    }

    func testUnknownBarcodeShowsMessageAndNoDetection() async {
        let viewModel = ScannerViewModel(productLookup: MockLookup(result: .success(nil)))
        await viewModel.handleBarcode("5449000000996")

        XCTAssertNil(viewModel.detection)
        XCTAssertNotNil(viewModel.barcodeMessage)
    }

    func testNetworkFailureShowsMessageAndNoDetection() async {
        let viewModel = ScannerViewModel(productLookup: MockLookup(result: .failure(URLError(.notConnectedToInternet))))
        await viewModel.handleBarcode("5449000000996")

        XCTAssertNil(viewModel.detection)
        XCTAssertNotNil(viewModel.barcodeMessage)
        XCTAssertFalse(viewModel.isLookingUpBarcode)
    }

    func testRetakeClearsBarcodeMessage() async {
        let viewModel = ScannerViewModel(productLookup: MockLookup(result: .success(nil)))
        await viewModel.handleBarcode("5449000000996")
        viewModel.retake()
        XCTAssertNil(viewModel.barcodeMessage)
    }
}
