//
//  ClassifierService.swift
//  NutriVision
//

import Vision
import CoreML
import UIKit

struct ClassificationResult: Sendable, Equatable {
    let label: String
    let confidence: Float
}

enum ClassifierError: Error {
    case modelUnavailable
    case invalidImage
}

/// A `CVPixelBuffer` handed off from the capture queue to the classifier.
///
/// `CVPixelBuffer` is a CoreFoundation type and isn't `Sendable`, but a buffer
/// vended by AVFoundation is only mutated by its pool — and holding a Swift
/// reference retains it, so the pool can't recycle it while we're reading. The
/// buffer is never written to on either side of the hop.
nonisolated struct SendablePixelBuffer: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

actor ClassifierService {
    /// How many ranked guesses to surface. The top result drives the UI; the
    /// rest back the "not quite right?" alternatives list, which matters a lot
    /// while the model is a general-purpose ImageNet classifier.
    static let topResultCount = 5

    private var visionModel: VNCoreMLModel?
    private var request: VNCoreMLRequest?

    /// `MobileNetV2`'s generated initializer is main-actor isolated (it
    /// inherits the target's default actor isolation), so it's loaded here
    /// lazily via a main-actor hop rather than synchronously in `init`.
    private func loadModelIfNeeded() async throws -> VNCoreMLRequest {
        if let request { return request }

        let coreMLModel = try await MainActor.run {
            let configuration = MLModelConfiguration()
            // Let the Neural Engine take the work when it's available; it's
            // both faster and far cheaper thermally than the GPU for per-frame
            // inference.
            configuration.computeUnits = .all
            return try MobileNetV2(configuration: configuration).model
        }
        let visionModel = try VNCoreMLModel(for: coreMLModel)
        self.visionModel = visionModel

        // Vision recommends reusing a request rather than rebuilding it per
        // frame — it caches setup that's otherwise repeated on every inference.
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .centerCrop
        self.request = request
        return request
    }

    /// Classifies a camera frame directly from its pixel buffer.
    ///
    /// This is the hot path: it hands Vision the buffer AVFoundation already
    /// gave us, with no `CIImage`/`CGImage`/`UIImage` round trip in between.
    func classify(
        pixelBuffer: SendablePixelBuffer,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> [ClassificationResult] {
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer.buffer,
            orientation: orientation,
            options: [:]
        )
        return try await run(handler: handler)
    }

    /// Classifies a still image — the photo-picker path, and what the unit
    /// tests exercise.
    func classify(image: UIImage) async throws -> [ClassificationResult] {
        guard let cgImage = image.cgImage else { throw ClassifierError.invalidImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        return try await run(handler: handler)
    }

    private func run(handler: VNImageRequestHandler) async throws -> [ClassificationResult] {
        let request = try await loadModelIfNeeded()

        // `perform` is synchronous. Running it inside the actor serializes
        // inference for free — only one frame is ever in the model at a time,
        // so a slow frame applies backpressure instead of piling up.
        try handler.perform([request])

        guard let observations = request.results as? [VNClassificationObservation] else {
            return []
        }
        return observations
            .prefix(Self.topResultCount)
            .map { ClassificationResult(label: $0.identifier, confidence: $0.confidence) }
    }
}

extension CGImagePropertyOrientation {
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
