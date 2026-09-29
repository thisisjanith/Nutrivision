//
//  WatchBridge.swift
//  NutriVision
//
//  Phone side of the watch companion: pushes today's snapshot to the watch and
//  logs meals the watch sends back ("quick log").
//

import Foundation
import SwiftData
import WatchConnectivity

@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func pushSnapshot() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(DailySnapshot.load()) else { return }
        try? session.updateApplicationContext(["snapshot": data])
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.pushSnapshot() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    /// The watch sends `["quickLog": [name, calories, protein, carbs, fat]]`.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if let ml = message["quickWater"] as? Double {
            Task { @MainActor in
                Tracker.shared.addWater(milliliters: ml, context: PersistenceController.shared.mainContext)
                replyHandler(["ok": true])
            }
            return
        }
        guard let log = message["quickLog"] as? [String: Any], let name = log["name"] as? String,
              let calories = log["calories"] as? Double else {
            replyHandler(["ok": false]); return
        }
        let protein = log["protein"] as? Double ?? 0, carbs = log["carbs"] as? Double ?? 0, fat = log["fat"] as? Double ?? 0
        Task { @MainActor in
            let context = PersistenceController.shared.mainContext
            let meal = MealEntry(name: name, calories: calories, protein: protein, carbs: carbs, fat: fat, servingSize: "1 serving")
            context.insert(meal)
            Tracker.shared.mealSaved(meal, context: context)
            replyHandler(["ok": true])
        }
    }
}
