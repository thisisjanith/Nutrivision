//
//  WatchContentView.swift
//  NutriVisionWatch
//

import SwiftUI

struct WatchContentView: View {
    let model: WatchModel

    private let brand = Color(red: 0.12, green: 0.64, blue: 0.48)

    var body: some View {
        NavigationStack {
            TabView {
                rings
                quickLog
            }
            .tabViewStyle(.verticalPage)
            .navigationTitle("NutriVision")
        }
    }

    private var rings: some View {
        let s = model.snapshot
        return VStack(spacing: 6) {
            ZStack {
                Circle().stroke(brand.opacity(0.25), lineWidth: 12)
                Circle().trim(from: 0, to: s.calorieProgress)
                    .stroke(brand, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(s.caloriesRemaining.rounded()))").font(.system(.title2, design: .rounded).bold())
                    Text("kcal left").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 100, height: 100)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Calories")
            .accessibilityValue("\(Int(s.caloriesRemaining.rounded())) kilocalories left of \(Int(s.calorieGoal))")
            HStack(spacing: 10) {
                stat("P", s.protein, .pink)
                stat("C", s.carbs, .orange)
                stat("F", s.fat, .blue)
            }
            Label("\(Int(s.waterMl)) / \(Int(s.waterGoalMl)) ml", systemImage: "drop.fill")
                .font(.caption2).foregroundStyle(.blue)
        }
    }

    private func stat(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text("\(Int(value.rounded()))").font(.caption.bold()).foregroundStyle(color)
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private var quickLog: some View {
        List {
            Section("Quick log") {
                ForEach(model.quickFoods) { food in
                    Button {
                        model.log(food)
                    } label: {
                        HStack {
                            Text(food.name)
                            Spacer()
                            Text("\(Int(food.calories))").foregroundStyle(.secondary)
                        }
                    }
                }
                Button {
                    model.addWater(250)
                } label: {
                    Label("Water 250 ml", systemImage: "drop.fill").foregroundStyle(.blue)
                }
            }
            if let logged = model.lastLogged {
                Text("Logged \(logged)").font(.caption2).foregroundStyle(brand)
            }
            if let error = model.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
    }
}
