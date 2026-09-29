//
//  WatchModel.swift
//  NutriVisionWatch
//

import Foundation
import Observation
import WatchConnectivity

/// Receives today's snapshot from the phone and sends quick-log requests back.
@MainActor
@Observable
final class WatchModel: NSObject, WCSessionDelegate {
    var snapshot: DailySnapshot = .load()
    var lastLogged: String?
    var errorMessage: String?

    struct QuickFood: Identifiable {
        let id = UUID()
        let name: String
        let calories, protein, carbs, fat: Double
    }

    let quickFoods: [QuickFood] = [
        QuickFood(name: "Banana", calories: 105, protein: 1.3, carbs: 27, fat: 0.4),
        QuickFood(name: "Apple", calories: 95, protein: 0.5, carbs: 25, fat: 0.3),
        QuickFood(name: "Egg", calories: 72, protein: 6.3, carbs: 0.4, fat: 4.8),
        QuickFood(name: "Coffee w/ milk", calories: 30, protein: 1.5, carbs: 2.5, fat: 1.5),
        QuickFood(name: "Protein shake", calories: 150, protein: 25, carbs: 6, fat: 3),
        QuickFood(name: "Yogurt", calories: 100, protein: 17, carbs: 6, fat: 0.7),
    ]

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func log(_ food: QuickFood) {
        send(["quickLog": ["name": food.name, "calories": food.calories, "protein": food.protein,
                           "carbs": food.carbs, "fat": food.fat]], label: food.name)
        snapshot.calories += food.calories
        snapshot.protein += food.protein; snapshot.carbs += food.carbs; snapshot.fat += food.fat
    }

    func addWater(_ ml: Double) {
        send(["quickWater": ml], label: "\(Int(ml)) ml water")
        snapshot.waterMl += ml
    }

    private func send(_ message: [String: Any], label: String) {
        guard WCSession.default.isReachable else {
            errorMessage = "Open NutriVision on iPhone to log."
            return
        }
        errorMessage = nil
        WCSession.default.sendMessage(message, replyHandler: { [weak self] _ in
            Task { @MainActor in self?.lastLogged = label }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in self?.errorMessage = "Couldn't reach iPhone." }
        })
    }

    private func apply(context: [String: Any]) {
        guard let data = context["snapshot"] as? Data, let decoded = try? JSONDecoder().decode(DailySnapshot.self, from: data) else { return }
        snapshot = decoded
        decoded.save()
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context: context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.apply(context: applicationContext) }
    }
}
