//
//  ModelEvaluator.swift
//  NutriVision
//
//  Offline accuracy harness: runs a classifier over labelled images and
//  reports top-1 / top-5 accuracy. Used by tests, and pointed at a real
//  dataset with the NUTRIVISION_EVAL_DIR environment variable (one folder per
//  class, named after the class, containing images).
//

import Foundation
import UIKit

nonisolated struct LabeledSample: Sendable {
    let label: String
    let url: URL
}

nonisolated struct EvaluationReport: Equatable, Sendable {
    var total = 0
    var top1Hits = 0
    var top5Hits = 0
    /// Per-class (hits, total) at top-1, to spot the weak classes.
    var perClass: [String: (hits: Int, total: Int)] = [:]

    var top1Accuracy: Double { total == 0 ? 0 : Double(top1Hits) / Double(total) }
    var top5Accuracy: Double { total == 0 ? 0 : Double(top5Hits) / Double(total) }

    static func == (lhs: EvaluationReport, rhs: EvaluationReport) -> Bool {
        lhs.total == rhs.total && lhs.top1Hits == rhs.top1Hits && lhs.top5Hits == rhs.top5Hits
    }

    var summary: String {
        let weakest = perClass.filter { $0.value.total > 0 }
            .sorted { Double($0.value.hits) / Double($0.value.total) < Double($1.value.hits) / Double($1.value.total) }
            .prefix(5)
            .map { "\($0.key) \($0.value.hits)/\($0.value.total)" }
            .joined(separator: ", ")
        return String(format: "n=%d top1=%.1f%% top5=%.1f%% weakest: %@", total, top1Accuracy * 100, top5Accuracy * 100, weakest)
    }
}

nonisolated enum ModelEvaluator {
    /// Model labels are synonym lists ("hotdog, hot dog, red hot") and may use
    /// underscores; a prediction is correct if any synonym equals the truth.
    static func matches(prediction: String, truth: String) -> Bool {
        func normalize(_ text: String) -> String {
            text.lowercased().replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        }
        let target = normalize(truth)
        return prediction.split(separator: ",").contains { normalize(String($0)) == target }
    }

    static func loadSamples(directory: URL) -> [LabeledSample] {
        let fm = FileManager.default
        guard let classes = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
        return classes.sorted { $0.lastPathComponent < $1.lastPathComponent }.flatMap { folder -> [LabeledSample] in
            let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            return files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
                .map { LabeledSample(label: folder.lastPathComponent, url: $0) }
        }
    }

    static func evaluate(samples: [LabeledSample], classifier: any FoodClassifying) async -> EvaluationReport {
        var report = EvaluationReport()
        for sample in samples {
            guard let image = UIImage(contentsOfFile: sample.url.path),
                  let results = try? await classifier.classify(image: image) else { continue }
            report.total += 1
            let ranked = results.map(\.label)
            let hit1 = ranked.first.map { matches(prediction: $0, truth: sample.label) } ?? false
            let hit5 = ranked.prefix(5).contains { matches(prediction: $0, truth: sample.label) }
            if hit1 { report.top1Hits += 1 }
            if hit5 { report.top5Hits += 1 }
            var entry = report.perClass[sample.label] ?? (0, 0)
            entry.total += 1
            if hit1 { entry.hits += 1 }
            report.perClass[sample.label] = entry
        }
        return report
    }
}
