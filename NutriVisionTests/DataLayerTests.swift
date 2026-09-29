//
//  DataLayerTests.swift
//  NutriVisionTests
//

import XCTest
import UserNotifications
@testable import NutriVision

final class FoodDatabaseTests: XCTestCase {
    private let database = FoodDatabase(foods: [
        FoodRecord(name: "Banana", kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, fiber: 2.6, sugar: 12, sodiumMg: 1, satFat: 0.1,
                   servings: [.init(label: "1 medium", grams: 118)], aliases: "bananas"),
        FoodRecord(name: "Banana Bread", kcal: 326, protein: 4, carbs: 55, fat: 10, fiber: 1.5, sugar: 30, sodiumMg: 300, satFat: 2,
                   servings: [.init(label: "1 slice", grams: 60)], aliases: ""),
        FoodRecord(name: "Greek Yogurt (plain)", kcal: 59, protein: 10, carbs: 3.6, fat: 0.4, fiber: 0, sugar: 3.2, sodiumMg: 36, satFat: 0.1,
                   servings: [.init(label: "1 cup", grams: 245)], aliases: "yoghurt"),
    ])

    func testExactNameOutranksLongerMatch() {
        XCTAssertEqual(database.search("banana").map(\.name), ["Banana", "Banana Bread"])
    }

    func testAliasAndMultiWordQueries() {
        XCTAssertEqual(database.search("yoghurt").first?.name, "Greek Yogurt (plain)")
        XCTAssertEqual(database.search("greek plain").first?.name, "Greek Yogurt (plain)")
        XCTAssertTrue(database.search("zzzz").isEmpty)
        XCTAssertTrue(database.search("   ").isEmpty)
    }

    func testProfileScalesFromPer100g() throws {
        let banana = try XCTUnwrap(database.food(named: "banana"))
        let profile = banana.profile(grams: 118, servingLabel: "1 medium")
        XCTAssertEqual(profile.calories, 89 * 1.18, accuracy: 0.01)
        XCTAssertEqual(profile.fiberGrams, 2.6 * 1.18, accuracy: 0.01)
        XCTAssertEqual(banana.servingOptions.map(\.label), ["1 medium", "100 g", "1 oz"])
    }

    func testParseGramsFromServingText() {
        XCTAssertEqual(ServingOption.parseGrams(from: "1 bar (40 g)"), 40)
        XCTAssertEqual(ServingOption.parseGrams(from: "250ml"), 250)
        XCTAssertNil(ServingOption.parseGrams(from: "1 medium"))
    }

    func testBundledDatabaseIsWellFormed() throws {
        let bundled = FoodDatabase.shared
        try XCTSkipIf(bundled.foods.isEmpty, "FoodDatabase.json not bundled in this test host")
        XCTAssertGreaterThan(bundled.foods.count, 100)
        for food in bundled.foods {
            XCTAssertGreaterThanOrEqual(food.kcal, 0, food.name)
            XCTAssertFalse(food.servings.isEmpty, "\(food.name) needs at least one serving")
            // Energy should roughly match 4/4/9 except alcohol.
            let estimate = food.protein * 4 + food.carbs * 4 + food.fat * 9
            if !["Beer", "Red Wine"].contains(food.name) {
                XCTAssertEqual(food.kcal, estimate, accuracy: max(30, food.kcal * 0.25), food.name)
            }
        }
        XCTAssertEqual(bundled.search("banana").first?.name, "Banana")
    }
}

final class InsightsEngineTests: XCTestCase {
    private func meal(daysAgo: Int, kcal: Double, protein: Double = 0, fiber: Double = 0) -> MealEntry {
        MealEntry(name: "m", calories: kcal, protein: protein, carbs: 0, fat: 0,
                  timestamp: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!, fiber: fiber)
    }

    func testDailyTotalsIncludeEmptyDaysOldestFirst() {
        let days = InsightsEngine.dailyTotals(meals: [meal(daysAgo: 0, kcal: 500), meal(daysAgo: 0, kcal: 250), meal(daysAgo: 2, kcal: 900)], days: 4)
        XCTAssertEqual(days.count, 4)
        XCTAssertTrue(days[0].date < days[3].date)
        XCTAssertEqual(days[3].calories, 750)
        XCTAssertEqual(days[3].mealCount, 2)
        XCTAssertFalse(days[2].isLogged)
        XCTAssertEqual(days[1].calories, 900)
    }

    func testStreakIgnoresEmptyTodayButBreaksOnGap() {
        // Logged yesterday and the day before; today empty -> streak of 2.
        let days = InsightsEngine.dailyTotals(meals: [meal(daysAgo: 1, kcal: 1), meal(daysAgo: 2, kcal: 1), meal(daysAgo: 4, kcal: 1)], days: 6)
        XCTAssertEqual(InsightsEngine.currentStreak(days), 2)
        XCTAssertEqual(InsightsEngine.longestStreak(days), 2)
    }

    func testConsistencyScore() {
        let onTarget = (0..<7).map { meal(daysAgo: $0, kcal: 2000) }
        let days = InsightsEngine.dailyTotals(meals: onTarget, days: 7)
        XCTAssertEqual(InsightsEngine.consistencyScore(days, calorieGoal: 2000), 100)
        XCTAssertEqual(InsightsEngine.consistencyScore(days, calorieGoal: 1000), 50)
        XCTAssertEqual(InsightsEngine.consistencyScore([], calorieGoal: 2000), 0)
    }

    func testLowProteinCardAppearsWhenBelowGoalOnMostDays() {
        let meals = (0..<5).map { meal(daysAgo: $0, kcal: 2000, protein: 40) }
        let days = InsightsEngine.dailyTotals(meals: meals, days: 7)
        let cards = InsightsEngine.cards(days: days, goals: MacroGoals(calories: 2000, protein: 120, carbs: 200, fat: 60), streak: 5)
        XCTAssertTrue(cards.contains { $0.id == "protein" && $0.tone == .warning && $0.title.contains("5 of 5") })
        XCTAssertTrue(cards.contains { $0.id == "streak" })
    }

    func testEmptyWeekPromptsToStartLogging() {
        let cards = InsightsEngine.cards(days: InsightsEngine.dailyTotals(meals: [], days: 7), goals: MacroGoals(calories: 2000, protein: 100, carbs: 200, fat: 60), streak: 0)
        XCTAssertEqual(cards.map(\.id), ["start"])
    }
}

final class HistoryFilterTests: XCTestCase {
    private func meal(_ name: String, daysAgo: Int) -> MealEntry {
        MealEntry(name: name, calories: 100, protein: 0, carbs: 0, fat: 0,
                  timestamp: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!)
    }

    func testWeekRangeKeepsSevenDaysAndDropsOlder() {
        let meals = [meal("today", daysAgo: 0), meal("six", daysAgo: 6), meal("seven", daysAgo: 7), meal("old", daysAgo: 40)]
        let names = MealHistoryFilter.meals(meals, range: .week).map(\.name)
        XCTAssertEqual(Set(names), ["today", "six"])
        XCTAssertEqual(MealHistoryFilter.meals(meals, range: .month).count, 3)
    }

    func testSearchFiltersByNameCaseInsensitively() {
        let meals = [meal("Banana", daysAgo: 0), meal("Pizza", daysAgo: 0)]
        XCTAssertEqual(MealHistoryFilter.meals(meals, range: .week, search: "banA").map(\.name), ["Banana"])
    }

    func testGroupingLabelsTodayAndYesterday() {
        let grouped = MealHistoryFilter.groupByDate([meal("a", daysAgo: 0), meal("b", daysAgo: 1), meal("c", daysAgo: 3)])
        XCTAssertEqual(grouped.map(\.title).prefix(2), ["TODAY", "YESTERDAY"])
        XCTAssertEqual(grouped.count, 3)
    }
}

@MainActor
final class DashboardViewModelTests: XCTestCase {
    private func makeStore() -> ProfileStore {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return ProfileStore(defaults: defaults)
    }

    func testTotalsSumAcrossMeals() {
        let viewModel = DashboardViewModel(profileStore: makeStore())
        let totals = viewModel.macroTotals(for: [
            MealEntry(name: "a", calories: 300, protein: 20, carbs: 30, fat: 10),
            MealEntry(name: "b", calories: 200, protein: 5, carbs: 40, fat: 2),
        ])
        XCTAssertEqual(totals.calories, 500)
        XCTAssertEqual(totals.protein, 25)
        XCTAssertEqual(totals.carbs, 70)
        XCTAssertEqual(totals.fat, 12)
    }

    func testGoalProgressClampsToUnitRange() {
        let store = makeStore()
        store.profile.calorieOverride = 2000
        let viewModel = DashboardViewModel(profileStore: store)
        XCTAssertEqual(viewModel.goalProgress(consumed: 1000), 0.5, accuracy: 0.0001)
        XCTAssertEqual(viewModel.goalProgress(consumed: 5000), 1)
        XCTAssertEqual(viewModel.goalProgress(consumed: -5), 0)
    }

    func testMealsGroupedInDayOrderSkippingEmptyTypes() {
        let viewModel = DashboardViewModel(profileStore: makeStore())
        let groups = viewModel.groupedByMealType([
            MealEntry(name: "dinner", calories: 1, protein: 0, carbs: 0, fat: 0, mealType: .dinner),
            MealEntry(name: "breakfast", calories: 1, protein: 0, carbs: 0, fat: 0, mealType: .breakfast),
        ])
        XCTAssertEqual(groups.map(\.type), [.breakfast, .dinner])
    }

    func testGreetingUsesProfileNameOrFallback() {
        let store = makeStore()
        XCTAssertTrue(DashboardViewModel(profileStore: store).greeting.hasSuffix("there"))
        store.profile.name = "Ada"
        XCTAssertTrue(DashboardViewModel(profileStore: store).greeting.hasSuffix("Ada"))
    }

    func testProfileRoundTripsThroughDefaults() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let first = ProfileStore(defaults: defaults)
        first.profile.name = "Grace"
        first.profile.diet = .keto
        let second = ProfileStore(defaults: defaults)
        XCTAssertEqual(second.profile.name, "Grace")
        XCTAssertEqual(second.profile.diet, .keto)
    }
}

final class MealTypeAndExportTests: XCTestCase {
    func testSuggestedMealTypeByHour() {
        func date(_ hour: Int) -> Date { Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())! }
        XCTAssertEqual(MealType.suggested(for: date(8)), .breakfast)
        XCTAssertEqual(MealType.suggested(for: date(13)), .lunch)
        XCTAssertEqual(MealType.suggested(for: date(19)), .dinner)
        XCTAssertEqual(MealType.suggested(for: date(23)), .snack)
        XCTAssertEqual(MealType.suggested(for: date(16)), .snack)
    }

    func testCSVEscapesCommasAndQuotes() {
        XCTAssertEqual(ExportService.csvField("plain"), "plain")
        XCTAssertEqual(ExportService.csvField("a, b"), "\"a, b\"")
        XCTAssertEqual(ExportService.csvField("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testCSVHasHeaderAndOneRowPerMeal() {
        let csv = ExportService.csv(meals: [
            MealEntry(name: "Eggs, scrambled", calories: 200, protein: 12, carbs: 2, fat: 15),
            MealEntry(name: "Toast", calories: 80, protein: 3, carbs: 15, fat: 1),
        ])
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, Substring(ExportService.csvHeader))
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(csv.contains("\"Eggs, scrambled\""))
    }

    func testPDFIsGenerated() {
        let data = ExportService.pdf(meals: [MealEntry(name: "Toast", calories: 80, protein: 3, carbs: 15, fat: 1)])
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
    }

    func testReminderRequestsOnlyForEnabledMeals() {
        var reminders = MealReminder.defaults
        reminders[0].enabled = true
        reminders[0].hour = 7; reminders[0].minute = 45
        let requests = ReminderService.requests(for: reminders)
        XCTAssertEqual(requests.count, 1)
        let trigger = requests[0].trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.hour, 7)
        XCTAssertEqual(trigger?.dateComponents.minute, 45)
        XCTAssertEqual(trigger?.repeats, true)
    }

    func testSnapshotProgressAndRemaining() {
        var snapshot = DailySnapshot.empty
        snapshot.calorieGoal = 2000; snapshot.calories = 500
        XCTAssertEqual(snapshot.caloriesRemaining, 1500)
        XCTAssertEqual(snapshot.calorieProgress, 0.25, accuracy: 0.0001)
        snapshot.calories = 2500
        XCTAssertEqual(snapshot.caloriesRemaining, 0)
        XCTAssertEqual(snapshot.calorieProgress, 1)
    }
}
