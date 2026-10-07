//
//  MoreWidgets.swift
//  NutriVisionWidgets
//
//  Water and fasting widgets. Both read the same App Group data as the
//  Today widget.
//

import WidgetKit
import SwiftUI
import AppIntents

private let waterBlue = Color(red: 0.23, green: 0.56, blue: 0.96)
private let fastingPurple = Color(red: 0.55, green: 0.36, blue: 0.96)

// MARK: Water

struct WaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalorieEntry

    private var snapshot: DailySnapshot { entry.snapshot }
    private var progress: Double { snapshot.waterGoalMl > 0 ? min(snapshot.waterMl / snapshot.waterGoalMl, 1) : 0 }
    private var litres: String { (snapshot.waterMl / 1000).formatted(.number.precision(.fractionLength(0...2))) }
    private var goalLitres: String { (snapshot.waterGoalMl / 1000).formatted(.number.precision(.fractionLength(0...2))) }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: progress) { Image(systemName: "drop.fill") } currentValueLabel: {
                Text("\(Int(snapshot.waterMl / 100))")
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("\(litres) of \(goalLitres) L", systemImage: "drop.fill").font(.headline)
                Gauge(value: progress) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
            }
        case .systemMedium:
            HStack(spacing: 16) {
                summary
                VStack(spacing: 8) {
                    addButton(250)
                    addButton(500)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                summary
                addButton(250)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Water", systemImage: "drop.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(waterBlue)
            Text("\(litres) L")
                .font(.system(.title, design: .rounded).bold())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.numericText())
            ProgressView(value: progress).tint(waterBlue)
            Text("of \(goalLitres) L").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addButton(_ ml: Int) -> some View {
        Button(intent: AddWaterIntent(milliliters: ml)) {
            Text("+\(ml) ml")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(waterBlue)
    }
}

struct WaterWidget: Widget {
    let kind = "WaterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieProvider()) { entry in
            WaterWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Water")
        .description("Today's water intake with one-tap logging.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: Fasting

struct FastingEntry: TimelineEntry {
    let date: Date
    let start: Date?
    let goalHours: Double
}

struct FastingProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastingEntry {
        FastingEntry(date: .now, start: .now.addingTimeInterval(-9 * 3600), goalHours: 16)
    }

    func getSnapshot(in context: Context, completion: @escaping (FastingEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastingEntry>) -> Void) {
        let entry = current()
        // Timer text counts on its own; refresh only to flip to "Goal reached".
        let next = entry.start.map { $0.addingTimeInterval(entry.goalHours * 3600) }.flatMap { $0 > .now ? $0 : nil }
            ?? Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func current() -> FastingEntry {
        FastingEntry(date: .now, start: FastingStore.start, goalHours: FastingStore.goalHours)
    }
}

struct FastingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FastingEntry

    private var end: Date? { entry.start.map { $0.addingTimeInterval(entry.goalHours * 3600) } }

    var body: some View {
        switch family {
        case .accessoryCircular:
            if let start = entry.start, let end {
                Gauge(value: min(max(Date.now.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)) {
                    Image(systemName: "timer")
                } currentValueLabel: {
                    Text("\(Int(Date.now.timeIntervalSince(start) / 3600))h")
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                Image(systemName: "timer")
            }
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("Fasting", systemImage: "timer").font(.headline)
                if let start = entry.start, let end {
                    Text(timerInterval: start...end, countsDown: false).monospacedDigit()
                } else {
                    Text("Not fasting")
                }
            }
        default:
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Fasting", systemImage: "timer")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(fastingPurple)
            if let start = entry.start, let end {
                Text(timerInterval: start...end, countsDown: false)
                    .font(.system(.title, design: .rounded).bold())
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                ProgressView(timerInterval: start...end, countsDown: false) { EmptyView() }.tint(fastingPurple)
                Text(end > .now ? "Ends \(end.formatted(date: .omitted, time: .shortened))" : "Goal reached")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(Int(entry.goalHours)) h")
                    .font(.system(.title, design: .rounded).bold())
                Text("Ready to start").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Open the app to begin").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct FastingWidget: Widget {
    let kind = "FastingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FastingProvider()) { entry in
            FastingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fasting")
        .description("Your fasting timer and progress toward your goal.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
