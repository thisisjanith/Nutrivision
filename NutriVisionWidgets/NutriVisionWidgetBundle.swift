//
//  NutriVisionWidgetBundle.swift
//  NutriVisionWidgets
//

import WidgetKit
import SwiftUI

@main
struct NutriVisionWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalorieWidget()
        WaterWidget()
        FastingWidget()
        FastingLiveActivity()
    }
}
