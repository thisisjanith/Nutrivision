//
//  MacroRingView.swift
//  NutriVision
//

import SwiftUI

/// Three concentric progress rings — protein (outer), carbs (middle), fat
/// (inner) — with the day's total calories centered inside.
struct MacroRingView: View {
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var totalCalories: Double

    private var maxValue: Double {
        max(proteinGrams, carbsGrams, fatGrams, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let lineWidth = side * 0.09
            let spacing = side * 0.03

            ZStack {
                ring(progress: proteinGrams / maxValue, color: .macroProtein, lineWidth: lineWidth)
                    .padding(0)
                ring(progress: carbsGrams / maxValue, color: .macroCarbs, lineWidth: lineWidth)
                    .padding(lineWidth + spacing)
                ring(progress: fatGrams / maxValue, color: .macroFat, lineWidth: lineWidth)
                    .padding((lineWidth + spacing) * 2)

                VStack(spacing: 2) {
                    Text("\(Int(totalCalories.rounded()))")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .contentTransition(.numericText())
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                    Text("KCAL TODAY")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                }
                .padding((lineWidth + spacing) * 2 + lineWidth)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: proteinGrams)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: carbsGrams)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: fatGrams)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(totalCalories.rounded())) kilocalories today")
    }

    private func ring(progress: Double, color: Color, lineWidth: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

#Preview {
    MacroRingView(proteinGrams: 112, carbsGrams: 140, fatGrams: 42, totalCalories: 1450)
        .frame(width: 200, height: 200)
        .padding()
}

#Preview("Dark") {
    MacroRingView(proteinGrams: 112, carbsGrams: 140, fatGrams: 42, totalCalories: 1450)
        .frame(width: 200, height: 200)
        .padding()
        .preferredColorScheme(.dark)
}
