//
//  CalorieWidget.swift
//  NutriVisionWidgets
//
//  Home and Lock Screen widgets showing today's calories and macros, with
//  interactive buttons (scan, add water) that run App Intents.
//

import WidgetKit
import SwiftUI
import AppIntents

struct CalorieEntry: TimelineEntry {
    let date: Date
    let snapshot: DailySnapshot
}

struct CalorieProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalorieEntry {
        CalorieEntry(date: .now, snapshot: DailySnapshot(date: .now, calories: 1200, calorieGoal: 2000, protein: 70, carbs: 140,
                                                         fat: 40, proteinGoal: 120, carbsGoal: 220, fatGoal: 65, waterMl: 1000, waterGoalMl: 2500))
    }

    func getSnapshot(in context: Context, completion: @escaping (CalorieEntry) -> Void) {
        completion(CalorieEntry(date: .now, snapshot: context.isPreview ? placeholder(in: context).snapshot : DailySnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalorieEntry>) -> Void) {
        let entry = CalorieEntry(date: .now, snapshot: DailySnapshot.load())
        // The app reloads timelines on every change; this refresh only covers
        // the midnight rollover and stale data.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

private let brand = Color(red: 0.12, green: 0.64, blue: 0.48)

struct CalorieRing: View {
    let snapshot: DailySnapshot
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(brand.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: snapshot.calorieProgress)
                .stroke(snapshot.calories > snapshot.calorieGoal ? Color.orange : brand,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int(snapshot.caloriesRemaining.rounded()))")
                    .font(.system(.title2, design: .rounded).bold())
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text("kcal left").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
}

struct MacroBar: View {
    let label: String, value: Double, goal: Double, color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption2)
                Spacer()
                Text("\(Int(value.rounded()))/\(Int(goal.rounded()))g").font(.caption2).foregroundStyle(.secondary)
            }
            ProgressView(value: min(value, max(goal, 1)), total: max(goal, 1)).tint(color)
        }
    }
}

struct CalorieWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalorieEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.snapshot.calorieProgress) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(Int(entry.snapshot.caloriesRemaining.rounded()))")
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("\(Int(entry.snapshot.caloriesRemaining.rounded())) kcal left").font(.headline)
                Gauge(value: entry.snapshot.calorieProgress) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
                Text("P \(Int(entry.snapshot.protein))  C \(Int(entry.snapshot.carbs))  F \(Int(entry.snapshot.fat))").font(.caption2)
            }
        case .accessoryInline:
            Text("\(Int(entry.snapshot.caloriesRemaining.rounded())) kcal left")
        case .systemMedium:
            medium
        case .systemLarge:
            large
        default:
            small
        }
    }

    private var small: some View {
        VStack(spacing: 6) {
            CalorieRing(snapshot: entry.snapshot, lineWidth: 9).padding(4)
            Button(intent: OpenScannerIntent()) {
                Label("Scan", systemImage: "camera.fill").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(brand)
        }
    }

    private var large: some View {
        VStack(spacing: 14) {
            CalorieRing(snapshot: entry.snapshot, lineWidth: 14).frame(width: 130, height: 130)
            VStack(spacing: 10) {
                MacroBar(label: "Protein", value: entry.snapshot.protein, goal: entry.snapshot.proteinGoal, color: Color(red: 0.91, green: 0.33, blue: 0.44))
                MacroBar(label: "Carbs", value: entry.snapshot.carbs, goal: entry.snapshot.carbsGoal, color: Color(red: 0.95, green: 0.66, blue: 0.23))
                MacroBar(label: "Fat", value: entry.snapshot.fat, goal: entry.snapshot.fatGoal, color: Color(red: 0.23, green: 0.51, blue: 0.85))
            }
            HStack {
                Button(intent: AddWaterIntent(milliliters: 250)) {
                    Label("+250 ml", systemImage: "drop.fill").font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .tint(.blue)
                Button(intent: OpenScannerIntent()) {
                    Label("Scan", systemImage: "camera.fill").font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .tint(brand)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            CalorieRing(snapshot: entry.snapshot).frame(width: 96)
            VStack(spacing: 6) {
                MacroBar(label: "Protein", value: entry.snapshot.protein, goal: entry.snapshot.proteinGoal, color: Color(red: 0.91, green: 0.33, blue: 0.44))
                MacroBar(label: "Carbs", value: entry.snapshot.carbs, goal: entry.snapshot.carbsGoal, color: Color(red: 0.95, green: 0.66, blue: 0.23))
                MacroBar(label: "Fat", value: entry.snapshot.fat, goal: entry.snapshot.fatGoal, color: Color(red: 0.23, green: 0.51, blue: 0.85))
                HStack {
                    Button(intent: AddWaterIntent(milliliters: 250)) {
                        Label("+250 ml", systemImage: "drop.fill").font(.caption2.weight(.semibold))
                    }
                    .tint(.blue)
                    Button(intent: OpenScannerIntent()) {
                        Label("Scan", systemImage: "camera.fill").font(.caption2.weight(.semibold))
                    }
                    .tint(brand)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct CalorieWidget: Widget {
    let kind = "CalorieWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalorieProvider()) { entry in
            CalorieWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Calories left and macro progress, with quick scan and water buttons.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
