//
//  ScannerViewModelTests.swift
//  NutriVisionTests
//
//  Exercises the scanner pipeline through its protocol seams (classifier,
//  vision client, product lookup, nutrition source) with stubs, so no camera,
//  network or model is involved.
//

import XCTest
import SwiftUI
import UIKit
@testable import NutriVision

private struct StubClassifier: FoodClassifying {
    var results: [ClassificationResult]
    func classify(image: UIImage) async throws -> [ClassificationResult] { results }
}

private struct StubDetector: FoodRegionDetector {
    func detect(in frame: SendablePixelBuffer) async -> FoodRegion? { nil }
}

private struct StubVision: VisionLLMClient {
    var result: Result<CloudFoodEstimate, Error>
    func estimate(jpeg: Data, context: EstimateContext) async throws -> CloudFoodEstimate { try result.get() }
}

private struct StubLookup: ProductLookup {
    var profile: NutritionProfile?
    func product(barcode: String) async throws -> NutritionProfile? { profile }
}

private struct StubNutrition: NutritionSource {
    func nutrition(forLabel label: String) -> NutritionProfile? {
        label == "banana" ? NutritionProfile(displayName: "Banana", calories: 105, proteinGrams: 1, carbsGrams: 27, fatGrams: 0, servingSize: "1 medium") : nil
    }
}

@MainActor
final class ScannerViewModelTests: XCTestCase {
    private let image: UIImage = {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { ctx in
            UIColor.yellow.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
    }()

    private func makeModel(vision: (any VisionLLMClient)? = nil, lookup: StubLookup = StubLookup()) -> ScannerViewModel {
        ScannerViewModel(
            productLookup: lookup, regionDetector: StubDetector(), visionClient: vision,
            classifier: StubClassifier(results: [ClassificationResult(label: "banana", confidence: 0.9), ClassificationResult(label: "orange", confidence: 0.05)]),
            nutritionSource: StubNutrition()
        )
    }

    func testPickedImageWithoutCloudFallsBackToClassifierAndNutritionSource() async {
        let model = makeModel()
        await model.classifyPickedImage(image)
        XCTAssertEqual(model.detection?.displayName, "Banana")
        XCTAssertEqual(model.detection?.nutrition?.calories, 105)
        XCTAssertEqual(model.detection?.alternatives.count, 1)
        XCTAssertNotNil(model.detection?.imageData)
        XCTAssertFalse(model.isAnalyzing)
    }

    func testCloudEstimateIsUsedAndMarkedEstimated() async {
        let estimate = CloudFoodEstimate(foodName: "Oatmeal", confidenceScore: 0.8, estimatedCalories: 300,
                                         macros: .init(protein: 10, carbs: 54, fat: 6), hiddenIngredientsFlag: true, portion: .medium)
        let model = makeModel(vision: StubVision(result: .success(estimate)))
        await model.classifyPickedImage(image)
        XCTAssertEqual(model.detection?.isCloudEstimate, true)
        XCTAssertEqual(model.detection?.isEstimated, true)
        XCTAssertEqual(model.detection?.estimate?.hiddenIngredientsFlag, true)
        XCTAssertEqual(model.detection?.nutrition?.calories, 300)
    }

    func testCloudFailureFallsBackToClassifierWithStatusMessage() async {
        let model = makeModel(vision: StubVision(result: .failure(VisionLLMError.badStatus(500))))
        await model.classifyPickedImage(image)
        XCTAssertEqual(model.detection?.displayName, "Banana")
        XCTAssertNotNil(model.statusMessage)
        XCTAssertEqual(model.detection?.isCloudEstimate, false)
    }

    func testPortionScaleFlowsIntoDraftMeal() async {
        let model = makeModel()
        await model.classifyPickedImage(image)
        model.detection?.portionScale = 2
        let draft = DraftMeal.from(detection: model.detection!)
        XCTAssertEqual(draft.baseCalories, 210)
        XCTAssertEqual(draft.carbsGrams, 54)
    }

    func testBarcodeHitProducesExactReading() async {
        let profile = NutritionProfile(displayName: "Bar", calories: 180, proteinGrams: 4, carbsGrams: 26, fatGrams: 7, servingSize: "1 bar (40 g)")
        let model = makeModel(lookup: StubLookup(profile: profile))
        await model.handleBarcode("012345678905")
        XCTAssertEqual(model.detection?.isBarcodeScan, true)
        XCTAssertEqual(model.detection?.isExact, true)
        XCTAssertEqual(model.detection?.confidence, 1)
    }

    func testBarcodeMissSetsMessageAndNoDetection() async {
        let model = makeModel(lookup: StubLookup(profile: nil))
        await model.handleBarcode("012345678905")
        XCTAssertNil(model.detection)
        XCTAssertNotNil(model.barcodeMessage)
    }

    func testDraftFromDatabaseFoodConvertsUnits() throws {
        let food = try XCTUnwrap(FoodDatabase(foods: [
            FoodRecord(name: "Rice", kcal: 130, protein: 2.7, carbs: 28, fat: 0.3, fiber: 0.4, sugar: 0, sodiumMg: 1, satFat: 0.1,
                       servings: [.init(label: "1 cup", grams: 158)], aliases: "")
        ]).foods.first)
        let draft = DraftMeal.from(food: food)
        XCTAssertEqual(draft.servingOptions.first?.label, "1 cup")
        XCTAssertEqual(draft.baseCalories ?? 0, 130 * 1.58, accuracy: 0.01)
        XCTAssertEqual(draft.servingOptions.map(\.grams), [158, 100, 28.3495])
    }
}

final class ModelEvaluatorTests: XCTestCase {
    func testSynonymAndUnderscoreMatching() {
        XCTAssertTrue(ModelEvaluator.matches(prediction: "hotdog, hot dog, red hot", truth: "hot dog"))
        XCTAssertTrue(ModelEvaluator.matches(prediction: "apple_pie", truth: "apple pie"))
        XCTAssertFalse(ModelEvaluator.matches(prediction: "pizza", truth: "pasta"))
    }

    func testReportsTop1AndTop5() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("eval-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        for label in ["banana", "pizza"] {
            let folder = dir.appendingPathComponent(label)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
            try image.pngData()!.write(to: folder.appendingPathComponent("1.png"))
        }
        let samples = ModelEvaluator.loadSamples(directory: dir)
        XCTAssertEqual(samples.map(\.label), ["banana", "pizza"])

        // Always answers banana first and pizza second: banana is top-1, pizza only top-5.
        struct Fixed: FoodClassifying {
            func classify(image: UIImage) async throws -> [ClassificationResult] {
                [ClassificationResult(label: "banana", confidence: 0.6), ClassificationResult(label: "pizza", confidence: 0.3)]
            }
        }
        let report = await ModelEvaluator.evaluate(samples: samples, classifier: Fixed())
        XCTAssertEqual(report.total, 2)
        XCTAssertEqual(report.top1Accuracy, 0.5, accuracy: 0.0001)
        XCTAssertEqual(report.top5Accuracy, 1, accuracy: 0.0001)
    }

    /// Point NUTRIVISION_EVAL_DIR at a labelled dataset to measure the real model.
    func testRealModelOnLabelledDatasetWhenProvided() async throws {
        guard let path = ProcessInfo.processInfo.environment["NUTRIVISION_EVAL_DIR"] else {
            throw XCTSkip("Set NUTRIVISION_EVAL_DIR to a folder-per-class image set to run this.")
        }
        let samples = ModelEvaluator.loadSamples(directory: URL(fileURLWithPath: path))
        try XCTSkipIf(samples.isEmpty, "No images found")
        let report = await ModelEvaluator.evaluate(samples: samples, classifier: ClassifierService())
        print("MODEL EVAL: \(report.summary)")
        XCTAssertGreaterThan(report.top5Accuracy, 0.3)
    }
}

@MainActor
final class RenderSmokeTests: XCTestCase {
    /// Not pixel-diff snapshots (that needs a third-party library); these catch
    /// views that crash or collapse to nothing when rendered.
    private func render<V: View>(_ view: V, size: CGSize) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        return renderer.uiImage
    }

    func testMacroRingRendersAtRequestedSize() {
        let image = render(MacroRingView(proteinGrams: 80, carbsGrams: 120, fatGrams: 40, totalCalories: 1200,
                                         goals: MacroGoals(calories: 2000, protein: 120, carbs: 220, fat: 65)),
                           size: CGSize(width: 200, height: 200))
        XCTAssertEqual(image?.size, CGSize(width: 200, height: 200))
    }

    func testOnboardingRenders() {
        let store = ProfileStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        XCTAssertNotNil(render(OnboardingView(store: store, onFinish: {}), size: CGSize(width: 390, height: 780)))
    }
}
