//
//  InsightsEngine.swift
//  NutriVision
//
//  On-device analytics over logged meals: daily totals, streaks, a
//  consistency score and plain-language insight cards. Pure functions over
//  value types so it's cheap to test.
//

import Foundation

nonisolated struct DayTotal: Equatable, Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var sodiumMg: Double = 0
    var mealCount: Int = 0
    var isLogged: Bool { mealCount > 0 }
}

nonisolated struct InsightCard: Equatable, Identifiable, Sendable {
    enum Tone: Sendable { case good, neutral, warning }
    let id: String
    let systemImage: String
    let title: String
    let detail: String
    let tone: Tone
}

nonisolated enum InsightsEngine {
    /// Totals for each of the last `days` days ending today, oldest first,
    /// including empty days so charts and streaks see gaps.
    static func dailyTotals(meals: [MealEntry], days: Int, now: Date = Date(), calendar: Calendar = .current) -> [DayTotal] {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: DayTotal] = [:]
        for offset in 0..<days {
            if let day = calendar.date(byAdding: .day, value: -offset, to: today) { byDay[day] = DayTotal(date: day) }
        }
        for meal in meals {
            let day = calendar.startOfDay(for: meal.timestamp)
            guard var total = byDay[day] else { continue }
            total.calories += meal.calories
            total.protein += meal.proteinGrams
            total.carbs += meal.carbsGrams
            total.fat += meal.fatGrams
            total.fiber += meal.fiberGrams
            total.sodiumMg += meal.sodiumMg
            total.mealCount += 1
            byDay[day] = total
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// Consecutive logged days ending today; an empty today doesn't break a
    /// streak until the day is over.
    static func currentStreak(_ days: [DayTotal]) -> Int {
        var ordered = days.sorted { $0.date > $1.date }
        if ordered.first?.isLogged == false { ordered.removeFirst() }
        return ordered.prefix(while: \.isLogged).count
    }

    static func longestStreak(_ days: [DayTotal]) -> Int {
        var best = 0, run = 0
        for day in days.sorted(by: { $0.date < $1.date }) {
            run = day.isLogged ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    /// 0-100: half for how many days were logged, half for how many landed
    /// within 10% under to 15% over the calorie goal.
    static func consistencyScore(_ days: [DayTotal], calorieGoal: Double) -> Int {
        guard !days.isEmpty, calorieGoal > 0 else { return 0 }
        let logged = Double(days.filter(\.isLogged).count)
        let onTarget = Double(days.filter { $0.isLogged && $0.calories >= calorieGoal * 0.9 && $0.calories <= calorieGoal * 1.15 }.count)
        let n = Double(days.count)
        return Int((50 * logged / n + 50 * onTarget / n).rounded())
    }

    static func cards(days lastSeven: [DayTotal], goals: MacroGoals, streak: Int, waterAverageMl: Double? = nil, waterGoalMl: Double = 0) -> [InsightCard] {
        var cards: [InsightCard] = []
        let logged = lastSeven.filter(\.isLogged)

        if streak >= 3 {
            cards.append(InsightCard(id: "streak", systemImage: "flame.fill", title: "\(streak)-day streak",
                                     detail: "You've logged food \(streak) days in a row. Keep it going!", tone: .good))
        }
        guard !logged.isEmpty else {
            return cards + [InsightCard(id: "start", systemImage: "camera.fill", title: "Start logging",
                                        detail: "Scan a meal to unlock personalised insights.", tone: .neutral)]
        }

        let proteinLow = logged.filter { $0.protein < goals.protein * 0.85 }.count
        if proteinLow >= 3 {
            cards.append(InsightCard(id: "protein", systemImage: "fish.fill", title: "Protein below goal \(proteinLow) of \(logged.count) days",
                                     detail: "Add a protein-rich food such as eggs, yogurt, chicken or lentils.", tone: .warning))
        } else {
            cards.append(InsightCard(id: "protein", systemImage: "checkmark.seal.fill", title: "Protein on track",
                                     detail: "You hit your protein target on \(logged.count - proteinLow) of \(logged.count) logged days.", tone: .good))
        }

        let over = logged.filter { $0.calories > goals.calories * 1.15 }.count
        if over >= 3 {
            cards.append(InsightCard(id: "over", systemImage: "arrow.up.circle.fill", title: "Over calories \(over) of \(logged.count) days",
                                     detail: "Smaller portions or lighter snacks would bring you back to target.", tone: .warning))
        }

        let averageFiber = logged.reduce(0) { $0 + $1.fiber } / Double(logged.count)
        if averageFiber > 0, averageFiber < 20 {
            cards.append(InsightCard(id: "fiber", systemImage: "leaf.fill", title: "Fiber is low",
                                     detail: "You average \(Int(averageFiber.rounded())) g a day; aim for 25 g with more vegetables, fruit and whole grains.", tone: .warning))
        }

        let highSodium = logged.filter { $0.sodiumMg > 2300 }.count
        if highSodium >= 2 {
            cards.append(InsightCard(id: "sodium", systemImage: "drop.triangle.fill", title: "High sodium on \(highSodium) days",
                                     detail: "Over 2,300 mg a day. Processed and restaurant foods are the usual source.", tone: .warning))
        }

        if let water = waterAverageMl, waterGoalMl > 0, water < waterGoalMl * 0.6 {
            cards.append(InsightCard(id: "water", systemImage: "drop.fill", title: "Drink more water",
                                     detail: "You're averaging \(Int((water / waterGoalMl * 100).rounded()))% of your water goal.", tone: .warning))
        }
        return cards
    }
}
