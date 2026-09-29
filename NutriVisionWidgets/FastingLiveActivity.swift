//
//  FastingLiveActivity.swift
//  NutriVisionWidgets
//

import ActivityKit
import WidgetKit
import SwiftUI

struct FastingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FastingActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Label("Fasting", systemImage: "timer").font(.headline)
                Text(timerInterval: context.state.start...context.state.end, countsDown: false)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false) { EmptyView() }
                    .tint(.purple)
                Text("Goal: \(Int(context.attributes.goalHours)) hours").font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Label("Fast", systemImage: "timer").foregroundStyle(.purple) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.start...context.state.end, countsDown: false)
                        .monospacedDigit().frame(maxWidth: 80)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: context.state.start...context.state.end, countsDown: false) { EmptyView() }.tint(.purple)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(.purple)
            } compactTrailing: {
                Text(timerInterval: context.state.start...context.state.end, countsDown: false)
                    .monospacedDigit().frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.purple)
            }
        }
    }
}
