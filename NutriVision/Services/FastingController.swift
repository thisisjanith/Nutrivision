//
//  FastingController.swift
//  NutriVision
//

import Foundation
import ActivityKit
import Observation

/// Starts/stops the fasting timer and mirrors it into a Live Activity so the
/// countdown shows on the Lock Screen and Dynamic Island.
@MainActor
@Observable
final class FastingController {
    static let shared = FastingController()

    private(set) var startDate: Date? = FastingStore.start
    var goalHours: Double = FastingStore.goalHours {
        didSet { FastingStore.goalHours = goalHours }
    }

    var isFasting: Bool { startDate != nil }
    var endDate: Date? { startDate.map { $0.addingTimeInterval(goalHours * 3600) } }

    func elapsedFraction(now: Date = Date()) -> Double {
        guard let startDate else { return 0 }
        return min(max(now.timeIntervalSince(startDate) / (goalHours * 3600), 0), 1)
    }

    func start() {
        let now = Date()
        startDate = now
        FastingStore.start = now
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let end = endDate else { return }
        let attributes = FastingActivityAttributes(goalHours: goalHours)
        let state = FastingActivityAttributes.ContentState(start: now, end: end)
        _ = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: end.addingTimeInterval(3600)))
    }

    func stop() {
        startDate = nil
        FastingStore.start = nil
        Task {
            for activity in Activity<FastingActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
