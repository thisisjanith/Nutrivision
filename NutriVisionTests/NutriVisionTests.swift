//
//  NutriVisionTests.swift
//  NutriVisionTests
//

import XCTest
@testable import NutriVision

final class MealEntryTests: XCTestCase {
    func testMacroCaloriesUsesFourFourNineFormula() {
        let entry = MealEntry(name: "Grilled Chicken Salad", calories: 400, protein: 28, carbs: 45, fat: 12)
        // 28*4 + 45*4 + 12*9 = 112 + 180 + 108 = 400
        XCTAssertEqual(entry.macroCalories, 400, accuracy: 0.001)
    }

    func testMacroCaloriesWithZeroMacros() {
        let entry = MealEntry(name: "Water", calories: 0, protein: 0, carbs: 0, fat: 0)
        XCTAssertEqual(entry.macroCalories, 0, accuracy: 0.001)
    }

    func testIsLowConfidenceBelowThreshold() {
        let lowConfidence = MealEntry(name: "Mystery Food", calories: 100, protein: 5, carbs: 10, fat: 2, confidence: 0.42)
        XCTAssertTrue(lowConfidence.isLowConfidence)

        let highConfidence = MealEntry(name: "Apple", calories: 95, protein: 0.5, carbs: 25, fat: 0.3, confidence: 0.92)
        XCTAssertFalse(highConfidence.isLowConfidence)
    }

    func testIsLowConfidenceAtThresholdBoundary() {
        let atThreshold = MealEntry(name: "Banana", calories: 105, protein: 1.3, carbs: 27, fat: 0.4, confidence: 0.6)
        XCTAssertFalse(atThreshold.isLowConfidence, "0.6 should not count as low confidence — the cutoff is strictly below 0.6")
    }
}

final class FoodNutritionMapTests: XCTestCase {
    func testExactLabelLookupReturnsMappedProfile() {
        let profile = FoodNutritionMap.lookup(label: "banana")
        XCTAssertEqual(profile?.displayName, "Banana")
        XCTAssertEqual(profile?.calories, 105)
    }

    func testLookupIsCaseInsensitive() {
        let profile = FoodNutritionMap.lookup(label: "BANANA")
        XCTAssertEqual(profile?.displayName, "Banana")
    }

    func testImageNetSynonymLabelMatchesViaContains() {
        // MobileNetV2 often returns comma-separated ImageNet synonyms, e.g.
        // "Granny Smith, apple" rather than the bare class name.
        let profile = FoodNutritionMap.lookup(label: "Granny Smith, apple")
        XCTAssertEqual(profile?.displayName, "Apple")
    }

    func testUnknownLabelReturnsNil() {
        XCTAssertNil(FoodNutritionMap.lookup(label: "space shuttle"))
    }

    func testLowConfidenceThresholdConstant() {
        XCTAssertEqual(lowConfidenceThreshold, 0.6)
    }
}

final class ClassificationToNutritionMappingTests: XCTestCase {
    /// Simulates the classifier pipeline with a mocked classification
    /// result (bypassing the actual Vision/CoreML call) and asserts the
    /// raw label maps to the expected nutrition profile.
    func testMockedHighConfidenceClassificationMapsToNutrition() {
        let mockResult = ClassificationResult(label: "cheeseburger", confidence: 0.92)

        let profile = FoodNutritionMap.lookup(label: mockResult.label)

        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.displayName, "Cheeseburger")
        XCTAssertEqual(profile?.calories, 535)
        XCTAssertGreaterThanOrEqual(mockResult.confidence, lowConfidenceThreshold)
    }

    func testMockedLowConfidenceClassificationIsFlagged() {
        let mockResult = ClassificationResult(label: "pizza", confidence: 0.31)

        let profile = FoodNutritionMap.lookup(label: mockResult.label)

        XCTAssertNotNil(profile, "A low-confidence result can still resolve a profile — the UI decides whether to trust it")
        XCTAssertLessThan(mockResult.confidence, lowConfidenceThreshold)
    }
}
