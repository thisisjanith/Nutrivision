//
//  GoalsAndTrendTests.swift
//  NutriVisionTests
//

import XCTest
@testable import NutriVision

final class NutritionGoalsTests: XCTestCase {
    func testMifflinStJeorForMaleAndFemale() {
        // 10*80 + 6.25*180 - 5*30 + 5 = 1780
        XCTAssertEqual(NutritionGoals.bmr(sex: .male, weightKg: 80, heightCm: 180, age: 30), 1780, accuracy: 0.001)
        // 10*60 + 6.25*165 - 5*25 - 161 = 1345.25
        XCTAssertEqual(NutritionGoals.bmr(sex: .female, weightKg: 60, heightCm: 165, age: 25), 1345.25, accuracy: 0.001)
    }

    func testTDEEAppliesActivityMultiplier() {
        var profile = UserProfile()
        profile.sex = .male; profile.weightKg = 80; profile.heightCm = 180; profile.age = 30; profile.activity = .moderate
        XCTAssertEqual(NutritionGoals.tdee(profile), 1780 * 1.55, accuracy: 0.001)
    }

    func testLoseGoalSubtractsDeficitAndRespectsFloor() {
        var profile = UserProfile()
        profile.sex = .female; profile.weightKg = 50; profile.heightCm = 155; profile.age = 60; profile.activity = .sedentary
        profile.goal = .lose; profile.weeklyRateKg = 0.75
        // Maintenance is far below 1200 + deficit, so the floor applies.
        XCTAssertEqual(NutritionGoals.calorieTarget(profile), 1200)
    }

    func testGainGoalAddsSurplus() {
        var profile = UserProfile()
        profile.goal = .gain; profile.weeklyRateKg = 0.5
        let maintenance = NutritionGoals.tdee(profile)
        XCTAssertEqual(NutritionGoals.calorieTarget(profile), ((maintenance + 550) / 10).rounded() * 10, accuracy: 10)
    }

    func testOverrideWinsOverFormula() {
        var profile = UserProfile()
        profile.calorieOverride = 1750
        XCTAssertEqual(NutritionGoals.calorieTarget(profile), 1750)
    }

    func testMacroGoalsMatchPresetSplitAndRoughlyAddUp() {
        for preset in DietPreset.allCases {
            let goals = NutritionGoals.macroGoals(calories: 2000, diet: preset)
            let kcal = goals.protein * 4 + goals.carbs * 4 + goals.fat * 9
            XCTAssertEqual(kcal, 2000, accuracy: 25, "\(preset)")
        }
        XCTAssertEqual(NutritionGoals.macroGoals(calories: 2000, diet: .highProtein).protein, 175)
    }

    func testWaterGoalScalesWithWeightUnlessOverridden() {
        var profile = UserProfile()
        profile.weightKg = 70
        XCTAssertEqual(NutritionGoals.waterGoalMl(profile), 2450)
        profile.waterGoalMl = 3000
        XCTAssertEqual(NutritionGoals.waterGoalMl(profile), 3000)
    }

    func testUnitConversions() {
        XCTAssertEqual(UnitSystem.imperial.displayWeight(kg: 100), 220.462, accuracy: 0.001)
        XCTAssertEqual(UnitSystem.imperial.kilograms(fromDisplay: 220.462), 100, accuracy: 0.001)
        XCTAssertEqual(UnitSystem.imperial.heightText(cm: 180), "5 ft 11 in")
        XCTAssertEqual(UnitSystem.metric.weightText(kg: 72.34), "72.3 kg")
    }
}

final class WeightTrendTests: XCTestCase {
    private func series(days: Int, start: Double, perDay: Double, from origin: Date = Date()) -> [WeightPoint] {
        (0..<days).map { i in
            WeightPoint(date: Calendar.current.date(byAdding: .day, value: i - days + 1, to: origin)!, kilograms: start + perDay * Double(i))
        }
    }

    func testSlopeOfLinearSeries() throws {
        let slope = try XCTUnwrap(WeightTrend.slopeKgPerDay(series(days: 20, start: 80, perDay: -0.1)))
        XCTAssertEqual(slope, -0.1, accuracy: 0.001)
    }

    func testSlopeNilForSinglePoint() {
        XCTAssertNil(WeightTrend.slopeKgPerDay(series(days: 1, start: 80, perDay: 0)))
    }

    func testSmoothingDampensASpike() {
        var points = series(days: 5, start: 80, perDay: 0)
        points[3] = WeightPoint(date: points[3].date, kilograms: 84)
        let smoothed = WeightTrend.smoothed(points)
        XCTAssertLessThan(smoothed[3].kilograms, 82)
        XCTAssertEqual(smoothed[0].kilograms, 80)
    }

    func testETAOnlyWhenTrendingTowardTarget() {
        let now = Date()
        let towards = WeightTrend.etaToGoal(current: 80, target: 75, slopeKgPerDay: -0.1, from: now)
        XCTAssertEqual(towards?.timeIntervalSince(now) ?? 0, 50 * 86_400, accuracy: 1)
        XCTAssertNil(WeightTrend.etaToGoal(current: 80, target: 75, slopeKgPerDay: 0.1, from: now))
        XCTAssertNil(WeightTrend.etaToGoal(current: 80, target: 75, slopeKgPerDay: 0.001, from: now))
    }
}

final class AdaptiveGoalTests: XCTestCase {
    private func profile() -> UserProfile {
        var p = UserProfile()
        p.goal = .lose; p.weeklyRateKg = 0.5; p.sex = .male
        return p
    }

    private func intake(days: Int, kcal: Double) -> [Date: Double] {
        var result: [Date: Double] = [:]
        for i in 0..<days {
            result[Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -i, to: Date())!)] = kcal
        }
        return result
    }

    func testStaysQuietWithTooLittleData() {
        let weights = (0..<5).map { WeightPoint(date: Calendar.current.date(byAdding: .day, value: -$0, to: Date())!, kilograms: 80) }
        XCTAssertNil(AdaptiveGoal.suggestion(weights: weights, intakeByDay: intake(days: 5, kcal: 2000), profile: profile(), currentTarget: 2000))
    }

    func testInfersMaintenanceFromFlatWeightAndProposesDeficit() throws {
        // Flat weight on 2600 kcal/day means maintenance is 2600; a 0.5 kg/week
        // loss goal needs about 550 kcal less.
        let weights = (0..<21).map { WeightPoint(date: Calendar.current.date(byAdding: .day, value: -$0, to: Date())!, kilograms: 85) }
        let suggestion = try XCTUnwrap(AdaptiveGoal.suggestion(weights: weights, intakeByDay: intake(days: 21, kcal: 2600), profile: profile(), currentTarget: 2600))
        XCTAssertEqual(suggestion.estimatedMaintenance, 2600, accuracy: 5)
        XCTAssertEqual(suggestion.suggestedCalories, 2050, accuracy: 15)
    }

    func testNoSuggestionWhenAlreadyCloseToTarget() {
        let weights = (0..<21).map { WeightPoint(date: Calendar.current.date(byAdding: .day, value: -$0, to: Date())!, kilograms: 85) }
        XCTAssertNil(AdaptiveGoal.suggestion(weights: weights, intakeByDay: intake(days: 21, kcal: 2600), profile: profile(), currentTarget: 2050))
    }
}
