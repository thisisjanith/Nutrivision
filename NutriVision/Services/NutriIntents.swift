//
//  NutriIntents.swift
//  NutriVision
//
//  Siri / Shortcuts / interactive-widget actions. Compiled into both the app
//  and the widget extension; `perform()` bodies only touch shared defaults or
//  the app's own store, so they behave the same wherever they run.
//

import AppIntents
import Foundation

/// Where the app should land the next time it becomes active.
nonisolated enum PendingRoute {
    static let key = "nutrivision.pendingRoute"
    static func set(_ route: String) { AppGroup.defaults.set(route, forKey: key) }
    static func take() -> String? {
        let value = AppGroup.defaults.string(forKey: key)
        AppGroup.defaults.removeObject(forKey: key)
        return value
    }
}

struct OpenScannerIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Food"
    static let description = IntentDescription("Opens NutriVision straight to the scanner.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingRoute.set("scan")
        return .result()
    }
}

struct CaloriesLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Calories Left Today"
    static let description = IntentDescription("Tells you how many calories remain in today's goal.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = DailySnapshot.load()
        let left = Int(snapshot.caloriesRemaining.rounded())
        let eaten = Int(snapshot.calories.rounded())
        return .result(dialog: "You have \(left) calories left today. You've had \(eaten) of \(Int(snapshot.calorieGoal.rounded())).")
    }
}

struct AddWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Water"
    static let description = IntentDescription("Logs a glass of water.")

    @Parameter(title: "Milliliters", default: 250)
    var milliliters: Int

    init() {}
    init(milliliters: Int) { self.milliliters = milliliters }

    func perform() async throws -> some IntentResult {
        // Applied by the app on next launch when running in the widget
        // extension; the snapshot is bumped immediately so the UI updates now.
        var snapshot = DailySnapshot.load()
        snapshot.waterMl += Double(milliliters)
        snapshot.save()
        PendingWater.add(Double(milliliters))
        return .result()
    }
}

/// Water logged from outside the app process, drained into SwiftData when the
/// app next runs.
nonisolated enum PendingWater {
    static let key = "nutrivision.pendingWaterMl"
    static func add(_ ml: Double) {
        AppGroup.defaults.set(AppGroup.defaults.double(forKey: key) + ml, forKey: key)
    }
    static func take() -> Double {
        let value = AppGroup.defaults.double(forKey: key)
        AppGroup.defaults.removeObject(forKey: key)
        return value
    }
}
