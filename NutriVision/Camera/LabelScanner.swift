//
//  LabelScanner.swift
//  NutriVision
//

import Vision
import UIKit

/// Reads a Nutrition Facts panel with on-device text recognition.
nonisolated enum LabelScanner {
    static func recognizeLines(in cgImage: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Language correction "fixes" numbers and unit letters into words.
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    static func scan(image: UIImage) throws -> NutritionProfile? {
        guard let cgImage = image.cgImage else { return nil }
        return NutritionLabelParser.parse(lines: try recognizeLines(in: cgImage))
    }
}
