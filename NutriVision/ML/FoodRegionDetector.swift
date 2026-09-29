//
//  FoodRegionDetector.swift
//  NutriVision
//
//  Viewfinder intelligence: finds *where* food is, not *what* it is. The live
//  path only needs a box and a lock-on signal; identification happens on
//  capture (cloud model, with the on-device classifier as offline fallback).
//

import Vision
import CoreML
import CoreGraphics

nonisolated struct FoodRegion: Sendable, Equatable {
    enum Kind: String, Sendable { case food, beverage }

    /// Normalised (0...1) rect with a top-left origin.
    let box: CGRect
    let kind: Kind
    let confidence: Float

    /// Maps the normalised box into a view that shows the image aspect-filled.
    func viewRect(in viewSize: CGSize, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let shownWidth = imageSize.width * scale
        let shownHeight = imageSize.height * scale
        let offsetX = (viewSize.width - shownWidth) / 2
        let offsetY = (viewSize.height - shownHeight) / 2
        return CGRect(
            x: offsetX + box.minX * shownWidth,
            y: offsetY + box.minY * shownHeight,
            width: box.width * shownWidth,
            height: box.height * shownHeight
        )
    }

    /// Vision reports boxes with a bottom-left origin.
    static func fromVision(_ rect: CGRect, kind: Kind, confidence: Float) -> FoodRegion {
        FoodRegion(box: CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height), kind: kind, confidence: confidence)
    }
}

protocol FoodRegionDetector: Sendable {
    func detect(in frame: SendablePixelBuffer) async -> FoodRegion?
}

/// Runs a bundled Core ML object detector (e.g. YOLOv8-nano exported with
/// `coremltools`) trained on two classes: "food" and "beverage".
///
/// Drop the compiled model into the app target as `FoodDetector.mlpackage`
/// (see `Proxy/README.md`); until then `makeDefault()` uses the saliency
/// detector below.
nonisolated final class CoreMLFoodRegionDetector: FoodRegionDetector, @unchecked Sendable {
    private let request: VNCoreMLRequest

    init?(modelURL: URL) {
        guard let model = try? MLModel(contentsOf: modelURL, configuration: { let c = MLModelConfiguration(); c.computeUnits = .all; return c }()),
              let vision = try? VNCoreMLModel(for: model) else { return nil }
        let request = VNCoreMLRequest(model: vision)
        request.imageCropAndScaleOption = .scaleFill
        self.request = request
    }

    /// Callers run one detection at a time (the frame sampler applies
    /// backpressure), so the shared request is never used concurrently.
    func detect(in frame: SendablePixelBuffer) async -> FoodRegion? {
        try? VNImageRequestHandler(cvPixelBuffer: frame.buffer, options: [:]).perform([request])
        let objects = (request.results as? [VNRecognizedObjectObservation]) ?? []
        guard let best = objects.max(by: { $0.confidence < $1.confidence }) else { return nil }
        let label = best.labels.first?.identifier.lowercased() ?? "food"
        return .fromVision(best.boundingBox, kind: label.contains("bev") || label.contains("drink") ? .beverage : .food, confidence: best.confidence)
    }
}

/// Fallback when no trained detector is bundled: objectness saliency picks the
/// most prominent object, which on a plated meal is almost always the food.
/// Less precise than a trained detector and it can't tell food from a mug.
nonisolated final class SaliencyFoodRegionDetector: FoodRegionDetector, @unchecked Sendable {
    private let request = VNGenerateObjectnessBasedSaliencyImageRequest()

    func detect(in frame: SendablePixelBuffer) async -> FoodRegion? {
        try? VNImageRequestHandler(cvPixelBuffer: frame.buffer, options: [:]).perform([request])
        guard let salient = (request.results?.first)?.salientObjects?.max(by: { $0.confidence < $1.confidence }) else { return nil }
        // A "region" covering the whole frame means nothing stood out.
        let area = salient.boundingBox.width * salient.boundingBox.height
        guard area > 0.04, area < 0.9 else { return nil }
        return .fromVision(salient.boundingBox, kind: .food, confidence: salient.confidence)
    }
}

nonisolated enum FoodRegionDetectorFactory {
    static func makeDefault() -> any FoodRegionDetector {
        if let url = Bundle.main.url(forResource: "FoodDetector", withExtension: "mlmodelc"),
           let detector = CoreMLFoodRegionDetector(modelURL: url) {
            return detector
        }
        return SaliencyFoodRegionDetector()
    }
}

/// Exponentially smooths box motion so the overlay glides instead of jittering.
nonisolated struct BoxSmoother {
    var alpha: CGFloat
    private var current: CGRect?

    init(alpha: CGFloat = 0.4) { self.alpha = alpha }

    mutating func update(_ rect: CGRect) -> CGRect {
        guard let previous = current else { current = rect; return rect }
        let next = CGRect(
            x: previous.minX + (rect.minX - previous.minX) * alpha,
            y: previous.minY + (rect.minY - previous.minY) * alpha,
            width: previous.width + (rect.width - previous.width) * alpha,
            height: previous.height + (rect.height - previous.height) * alpha
        )
        current = next
        return next
    }

    mutating func reset() { current = nil }
}
