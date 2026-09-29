//
//  MealDetailView.swift
//  NutriVision
//

import SwiftUI
import SwiftData

struct DraftMeal: Identifiable {
    let id = UUID()
    var name: String
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var unitLabel: String
    var confidence: Double

    static func from(detection: DetectedFood) -> DraftMeal {
        guard let nutrition = detection.scaledNutrition else {
            return DraftMeal(
                name: detection.displayName,
                proteinGrams: 0,
                carbsGrams: 0,
                fatGrams: 0,
                unitLabel: "serving",
                confidence: Double(detection.confidence)
            )
        }
        return DraftMeal(
            name: nutrition.displayName,
            proteinGrams: nutrition.proteinGrams,
            carbsGrams: nutrition.carbsGrams,
            fatGrams: nutrition.fatGrams,
            unitLabel: nutrition.servingSize,
            confidence: Double(detection.confidence)
        )
    }
}

struct MealDetailView: View {
    let draft: DraftMeal

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var servingCount = 1
    @State private var proteinGrams: Double
    @State private var carbsGrams: Double
    @State private var fatGrams: Double

    init(draft: DraftMeal) {
        self.draft = draft
        _proteinGrams = State(initialValue: draft.proteinGrams)
        _carbsGrams = State(initialValue: draft.carbsGrams)
        _fatGrams = State(initialValue: draft.fatGrams)
    }

    private var kcalTotal: Double {
        proteinGrams * 4 + carbsGrams * 4 + fatGrams * 9
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, Theme.Spacing.sm)

            header

            servingRow

            VStack(spacing: Theme.Spacing.lg) {
                macroSlider(label: "Protein", color: .macroProtein, value: $proteinGrams, range: 0...200)
                macroSlider(label: "Carbs", color: .macroCarbs, value: $carbsGrams, range: 0...400)
                macroSlider(label: "Fat", color: .macroFat, value: $fatGrams, range: 0...150)
            }

            kcalTotalView

            saveButton
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        HStack {
            Text(draft.name)
                .font(.title3)
                .fontWeight(.bold)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .accessibilityLabel("Close")
        }
    }

    private var servingRow: some View {
        HStack {
            Text("Serving size")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
            HStack(spacing: Theme.Spacing.md) {
                Button {
                    guard servingCount > 1 else { return }
                    servingCount -= 1
                    applyServingScale()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 28)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }

                Text("\(servingCount) \(draft.unitLabel)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Button {
                    servingCount += 1
                    applyServingScale()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 28)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
            }
            .foregroundStyle(.primary)
            .buttonStyle(.plain)
        }
    }

    private func applyServingScale() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            proteinGrams = draft.proteinGrams * Double(servingCount)
            carbsGrams = draft.carbsGrams * Double(servingCount)
            fatGrams = draft.fatGrams * Double(servingCount)
        }
    }

    private func macroSlider(label: String, color: Color, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(color)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))g")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            Slider(value: value, in: range)
                .tint(color)
        }
    }

    private var kcalTotalView: some View {
        VStack(spacing: 2) {
            Text("\(Int(kcalTotal.rounded()))")
                .font(.system(.largeTitle, design: .rounded))
                .fontWeight(.bold)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("kcal total")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: kcalTotal)
    }

    private var saveButton: some View {
        Button {
            saveMeal()
        } label: {
            Text("Save to Log")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
    }

    private func saveMeal() {
        let entry = MealEntry(
            name: draft.name,
            calories: kcalTotal,
            protein: proteinGrams,
            carbs: carbsGrams,
            fat: fatGrams,
            confidence: draft.confidence,
            servingSize: "\(servingCount) \(draft.unitLabel)"
        )
        modelContext.insert(entry)
        dismiss()
    }
}

#Preview {
    MealDetailView(draft: DraftMeal(
        name: "Grilled Chicken Salad",
        proteinGrams: 28,
        carbsGrams: 45,
        fatGrams: 12,
        unitLabel: "bowl (250g)",
        confidence: 1.0
    ))
    .modelContainer(for: MealEntry.self, inMemory: true)
}
