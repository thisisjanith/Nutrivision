//
//  NutriVisionWatchApp.swift
//  NutriVisionWatch
//

import SwiftUI

@main
struct NutriVisionWatchApp: App {
    @State private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchContentView(model: model)
        }
    }
}
