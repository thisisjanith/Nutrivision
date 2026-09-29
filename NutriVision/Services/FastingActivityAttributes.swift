//
//  FastingActivityAttributes.swift
//  NutriVision
//
//  Shared between the app and the widget extension (both compile this file).
//

import ActivityKit
import Foundation

struct FastingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        var end: Date
    }

    var goalHours: Double
}
