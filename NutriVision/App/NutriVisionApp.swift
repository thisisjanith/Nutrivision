//
//  NutriVisionApp.swift
//  NutriVision
//

import SwiftUI
import SwiftData

@main
struct NutriVisionApp: App {
    init() {
        DiagnosticsSubscriber.shared.start()
        WatchBridge.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(PersistenceController.shared)
    }
}
