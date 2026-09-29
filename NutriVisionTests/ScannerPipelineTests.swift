//
//  ScannerPipelineTests.swift
//  NutriVisionTests
//

import XCTest
@testable import NutriVision

/// Covers the disambiguation rules added when the naive `contains` matcher
/// was replaced. Basic exact/case/synonym lookups live in `NutriVisionTests`.
final class FoodNutritionMapMatchingTests: XCTestCase {
    func testMoreSpecificKeyWinsOverShorterOne() {
        XCTAssertEqual(
            FoodNutritionMap.lookup(label: "butternut squash")?.displayName,
            "Butternut Squash"
        )
    }

    func testDoesNotMatchKeyInsideAnUnrelatedWord() {
        // Regression: substring matching let "corn" claim "popcorn" and "fig"
        // claim "figurine".
        XCTAssertNil(FoodNutritionMap.lookup(label: "popcorn"))
        XCTAssertNil(FoodNutritionMap.lookup(label: "figurine"))
    }

    func testLookupIsDeterministicAcrossRepeatedCalls() {
        // Regression: the old implementation iterated the profiles dictionary,
        // whose order is unspecified, so an ambiguous label could resolve to a
        // different food on each launch.
        let label = "hot pot, soup"
        let first = FoodNutritionMap.lookup(label: label)?.displayName
        XCTAssertNotNil(first)
        for _ in 0..<200 {
            XCTAssertEqual(FoodNutritionMap.lookup(label: label)?.displayName, first)
        }
    }

    func testPrettifiedClassLabelTakesFirstSynonymTitleCased() {
        XCTAssertEqual("hotdog, hot dog, red hot".prettifiedClassLabel, "Hotdog")
        XCTAssertEqual("bell pepper".prettifiedClassLabel, "Bell Pepper")
    }
}

final class DetectionStabilizerTests: XCTestCase {
    private func result(_ label: String, _ confidence: Float) -> ClassificationResult {
        ClassificationResult(label: label, confidence: confidence)
    }

    func testWithholdsLabelUntilItWinsAMajorityOfTheWindow() {
        var stabilizer = DetectionStabilizer(windowSize: 5, requiredAgreement: 3)
        XCTAssertNil(stabilizer.accept(result("pizza", 0.8)))
        XCTAssertNil(stabilizer.accept(result("pizza", 0.8)))
        XCTAssertNotNil(stabilizer.accept(result("pizza", 0.8)))
    }

    func testFlickeringLabelsNeverPublish() {
        var stabilizer = DetectionStabilizer(windowSize: 5, requiredAgreement: 3)
        // No label reaches 3 of any 5 consecutive frames in this sequence.
        for label in ["pizza", "bagel", "pretzel", "pizza", "bagel", "pretzel"] {
            XCTAssertNil(stabilizer.accept(result(label, 0.7)), "\(label) should not have stabilized")
        }
    }

    func testReportedConfidenceIsMeanOverAgreeingFrames() {
        var stabilizer = DetectionStabilizer(windowSize: 5, requiredAgreement: 3)
        _ = stabilizer.accept(result("pizza", 0.4))
        _ = stabilizer.accept(result("pizza", 0.6))
        let stable = stabilizer.accept(result("pizza", 0.8))
        // Mean of 0.4/0.6/0.8, not the 0.8 spike that happened to land last.
        XCTAssertEqual(stable?.confidence ?? 0, 0.6, accuracy: 0.0001)
    }

    func testWindowSlidesSoStaleFramesStopCounting() {
        var stabilizer = DetectionStabilizer(windowSize: 3, requiredAgreement: 2)
        _ = stabilizer.accept(result("pizza", 0.9))
        XCTAssertNil(stabilizer.accept(result("bagel", 0.9)))
        // "pizza" falls out of the 3-frame window here, so it can't combine
        // with a later frame to reach the threshold.
        XCTAssertNil(stabilizer.accept(result("pretzel", 0.9)))
        XCTAssertNil(stabilizer.accept(result("pizza", 0.9)))
    }

    func testResetClearsAccumulatedAgreement() {
        var stabilizer = DetectionStabilizer(windowSize: 5, requiredAgreement: 3)
        _ = stabilizer.accept(result("pizza", 0.8))
        _ = stabilizer.accept(result("pizza", 0.8))
        stabilizer.reset()
        XCTAssertNil(stabilizer.accept(result("pizza", 0.8)))
    }
}

@MainActor
final class DetectedFoodTests: XCTestCase {
    private func candidate(_ label: String, _ confidence: Float) -> FoodCandidate {
        FoodCandidate(
            rawLabel: label,
            confidence: confidence,
            nutrition: FoodNutritionMap.lookup(label: label)
        )
    }

    func testSelectingAnAlternativePromotesItAndDemotesThePrevious() {
        let primary = candidate("pizza", 0.5)
        let runnerUp = candidate("bagel", 0.3)
        let third = candidate("pretzel", 0.1)
        let detection = DetectedFood(candidate: primary, alternatives: [runnerUp, third])

        let corrected = detection.selecting(runnerUp)

        XCTAssertEqual(corrected.displayName, "Bagel")
        XCTAssertEqual(corrected.alternatives.map(\.displayName), ["Pizza", "Pretzel"])
    }

    func testUnmappedLabelStillShowsAReadableName() {
        let detection = DetectedFood(candidate: candidate("airliner", 0.9), alternatives: [])
        XCTAssertEqual(detection.displayName, "Airliner")
        XCTAssertFalse(detection.hasNutrition)
    }

    func testLowConfidenceUsesSharedThreshold() {
        XCTAssertTrue(DetectedFood(candidate: candidate("pizza", 0.59), alternatives: []).isLowConfidence)
        XCTAssertFalse(DetectedFood(candidate: candidate("pizza", 0.61), alternatives: []).isLowConfidence)
    }
}
