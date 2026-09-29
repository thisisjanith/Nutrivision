//
//  DetectionStabilizer.swift
//  NutriVision
//

import Foundation

/// Smooths a stream of per-frame classifications into a steady reading.
///
/// A classifier run frame-by-frame is noisy: the top label flips between near
/// neighbours ("plate" / "soup bowl" / "consomme") as the camera moves, which
/// makes the on-screen label strobe and, worse, means whatever label happens
/// to be showing when the user taps confirm is close to arbitrary.
///
/// So a label has to win a majority of a short rolling window before it's
/// published, and the confidence reported is its mean over that window rather
/// than one lucky frame's spike.
struct DetectionStabilizer {
    /// How many recent frames to consider.
    let windowSize: Int
    /// How many of those frames must agree before a label is published.
    let requiredAgreement: Int

    private var window: [ClassificationResult] = []

    init(windowSize: Int = 5, requiredAgreement: Int = 3) {
        precondition(requiredAgreement <= windowSize, "agreement threshold can't exceed the window")
        self.windowSize = windowSize
        self.requiredAgreement = requiredAgreement
    }

    mutating func reset() {
        window.removeAll(keepingCapacity: true)
    }

    /// Feeds one frame's top result in, and returns a result only once the
    /// window agrees on a label.
    mutating func accept(_ result: ClassificationResult) -> ClassificationResult? {
        window.append(result)
        if window.count > windowSize {
            window.removeFirst(window.count - windowSize)
        }

        let matches = window.filter { $0.label == result.label }
        guard matches.count >= requiredAgreement else { return nil }

        let meanConfidence = matches.reduce(Float(0)) { $0 + $1.confidence } / Float(matches.count)
        return ClassificationResult(label: result.label, confidence: meanConfidence)
    }
}
