//
//  WeightTrend.swift
//  NutriVision
//

import Foundation

nonisolated struct WeightPoint: Equatable, Sendable {
    let date: Date
    let kilograms: Double
}

nonisolated enum WeightTrend {
    /// Exponentially smoothed series (alpha 0.25), which hides day-to-day
    /// water-weight noise so the real direction shows.
    static func smoothed(_ points: [WeightPoint], alpha: Double = 0.25) -> [WeightPoint] {
        let sorted = points.sorted { $0.date < $1.date }
        var result: [WeightPoint] = []
        var current: Double?
        for point in sorted {
            let next = current.map { $0 + alpha * (point.kilograms - $0) } ?? point.kilograms
            current = next
            result.append(WeightPoint(date: point.date, kilograms: next))
        }
        return result
    }

    /// Least-squares slope in kg/day, or nil with fewer than 2 distinct days.
    static func slopeKgPerDay(_ points: [WeightPoint]) -> Double? {
        guard points.count >= 2, let first = points.map(\.date).min() else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = points.map(\.kilograms)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        let denominator = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        guard denominator > 0 else { return nil }
        let numerator = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        return numerator / denominator
    }

    /// When the trend line reaches `target`, or nil if it's flat or heading
    /// the wrong way.
    static func etaToGoal(current: Double, target: Double, slopeKgPerDay: Double, from date: Date = Date()) -> Date? {
        let remaining = target - current
        guard abs(remaining) > 0.05 else { return date }
        guard abs(slopeKgPerDay) > 0.005, (remaining > 0) == (slopeKgPerDay > 0) else { return nil }
        let days = remaining / slopeKgPerDay
        guard days < 3650 else { return nil }
        return date.addingTimeInterval(days * 86_400)
    }
}

nonisolated enum AdaptiveGoal {
    struct Suggestion: Equatable, Sendable {
        let estimatedMaintenance: Double
        let suggestedCalories: Double
    }

    /// Infers real maintenance calories from what the scale did versus what
    /// was eaten, then proposes a target that delivers the wanted rate.
    /// Needs a fortnight of weights and ten logged days or it stays quiet.
    static func suggestion(
        weights: [WeightPoint],
        intakeByDay: [Date: Double],
        profile: UserProfile,
        currentTarget: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Suggestion? {
        let windowStart = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        let recent = weights.filter { $0.date >= windowStart }
        guard let first = recent.map(\.date).min(), let last = recent.map(\.date).max(),
              last.timeIntervalSince(first) >= 13 * 86_400,
              let slope = WeightTrend.slopeKgPerDay(WeightTrend.smoothed(recent)) else { return nil }

        let loggedDays = intakeByDay.filter { $0.key >= calendar.startOfDay(for: windowStart) && $0.value > 300 }
        guard loggedDays.count >= 10 else { return nil }
        let averageIntake = loggedDays.values.reduce(0, +) / Double(loggedDays.count)

        let maintenance = averageIntake - slope * NutritionGoals.kcalPerKg
        let wantedDelta: Double
        switch profile.goal {
        case .maintain: wantedDelta = 0
        case .lose: wantedDelta = -profile.weeklyRateKg * NutritionGoals.kcalPerKg / 7
        case .gain: wantedDelta = profile.weeklyRateKg * NutritionGoals.kcalPerKg / 7
        }
        var suggested = maintenance + wantedDelta
        suggested = max(suggested, NutritionGoals.calorieFloor(for: profile.sex))
        suggested = (suggested / 10).rounded() * 10
        guard abs(suggested - currentTarget) >= 75 else { return nil }
        return Suggestion(estimatedMaintenance: maintenance.rounded(), suggestedCalories: suggested)
    }
}
