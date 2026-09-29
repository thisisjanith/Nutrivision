//
//  CachedEstimate.swift
//  NutriVision
//

import Foundation
import SwiftData
import Vision
import UIKit

/// A previously returned cloud estimate keyed by an embedding of the image it
/// came from, so a near-identical scan (same morning oatmeal) skips the network.
@Model
final class CachedEstimate {
    var id: UUID
    var createdAt: Date
    var lastUsedAt: Date
    var hitCount: Int
    /// JSON-encoded `CloudFoodEstimate`.
    var payload: Data
    /// Keyed-archived `VNFeaturePrintObservation`.
    var featurePrint: Data

    init(payload: Data, featurePrint: Data) {
        self.id = UUID()
        self.createdAt = Date()
        self.lastUsedAt = Date()
        self.hitCount = 0
        self.payload = payload
        self.featurePrint = featurePrint
    }
}

nonisolated enum ImageEmbedder {
    static func featurePrint(for image: UIImage) throws -> VNFeaturePrintObservation? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        #if targetEnvironment(simulator)
        // The simulator has no Neural Engine/GPU path for this request.
        request.usesCPUOnly = true
        #endif
        try VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation), options: [:])
            .perform([request])
        return request.results?.first
    }

    static func archive(_ observation: VNFeaturePrintObservation) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
    }

    static func unarchive(_ data: Data) -> VNFeaturePrintObservation? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }
}

@MainActor
final class EstimateCache {
    /// Feature-print distance under which two images count as the same meal.
    /// Identical images score 0; different plates score well above 0.5.
    static let matchDistance: Float = 0.3
    static let maxEntries = 200

    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    func lookup(image: UIImage) -> CloudFoodEstimate? {
        guard let query = try? ImageEmbedder.featurePrint(for: image) else { return nil }
        let entries = (try? context.fetch(FetchDescriptor<CachedEstimate>())) ?? []

        var best: (entry: CachedEstimate, distance: Float)?
        for entry in entries {
            guard let stored = ImageEmbedder.unarchive(entry.featurePrint) else { continue }
            var distance: Float = .greatestFiniteMagnitude
            guard (try? query.computeDistance(&distance, to: stored)) != nil else { continue }
            if distance < Self.matchDistance, distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (entry, distance)
            }
        }
        guard let hit = best, let estimate = try? JSONDecoder().decode(CloudFoodEstimate.self, from: hit.entry.payload) else {
            return nil
        }
        hit.entry.hitCount += 1
        hit.entry.lastUsedAt = Date()
        return estimate
    }

    func store(_ estimate: CloudFoodEstimate, image: UIImage) {
        guard let print = try? ImageEmbedder.featurePrint(for: image),
              let archived = ImageEmbedder.archive(print),
              let payload = try? JSONEncoder().encode(estimate) else { return }
        context.insert(CachedEstimate(payload: payload, featurePrint: archived))
        evictIfNeeded()
        try? context.save()
    }

    private func evictIfNeeded() {
        let descriptor = FetchDescriptor<CachedEstimate>(sortBy: [SortDescriptor(\.lastUsedAt)])
        guard let all = try? context.fetch(descriptor), all.count > Self.maxEntries else { return }
        for old in all.prefix(all.count - Self.maxEntries) { context.delete(old) }
    }
}
