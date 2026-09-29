//
//  MealDetailView.swift
//  NutriVision
//

import SwiftUI
import SwiftData
import UIKit

struct DraftMeal: Identifiable {
    let id = UUID()
    var name: String
    /// Macros for ONE unit of `servingOptions[0]` (or of `unitLabel` when
    /// there are no options).
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var unitLabel: String
    var confidence: Double
    var fiberGrams: Double = 0
    var sugarGrams: Double = 0
    var sodiumMg: Double = 0
    var saturatedFatGrams: Double = 0
    /// Source calories for one base unit. Kept so foods whose energy isn't
    /// 4/4/9 of their macros (alcohol, fibre) still log their real kcal;
    /// slider edits then move the total by the macro difference.
    var baseCalories: Double?
    /// Alternative units with gram weights; the first is the base unit.
    var servingOptions: [ServingOption] = []
    var photoData: Data?
    var mealType: MealType = .suggested()
    var timestamp = Date()
    /// Non-nil when editing an existing log entry rather than adding one.
    var editing: MealEntry?

    static func from(detection: DetectedFood) -> DraftMeal {
        guard let nutrition = detection.scaledNutrition else {
            return DraftMeal(
                name: detection.displayName, proteinGrams: 0, carbsGrams: 0, fatGrams: 0,
                unitLabel: "serving", confidence: Double(detection.confidence), photoData: detection.imageData
            )
        }
        var draft = from(profile: nutrition, confidence: Double(detection.confidence))
        draft.photoData = detection.imageData
        return draft
    }

    static func from(profile: NutritionProfile, confidence: Double = 1) -> DraftMeal {
        var draft = DraftMeal(
            name: profile.displayName, proteinGrams: profile.proteinGrams, carbsGrams: profile.carbsGrams,
            fatGrams: profile.fatGrams, unitLabel: profile.servingSize, confidence: confidence,
            fiberGrams: profile.fiberGrams, sugarGrams: profile.sugarGrams, sodiumMg: profile.sodiumMg,
            saturatedFatGrams: profile.saturatedFatGrams, baseCalories: profile.calories
        )
        // When the serving text states a weight ("1 bar (40 g)") we can offer
        // grams and ounces too.
        if let grams = ServingOption.parseGrams(from: profile.servingSize) {
            draft.servingOptions = [
                ServingOption(label: profile.servingSize, grams: grams),
                ServingOption(label: "100 g", grams: 100),
                ServingOption(label: "1 oz", grams: 28.3495),
            ]
        }
        return draft
    }

    static func from(food: FoodRecord) -> DraftMeal {
        var draft = from(profile: food.defaultProfile)
        // Recompute per-unit values from per-100g so every unit converts exactly.
        let options = food.servingOptions
        draft.servingOptions = options
        draft.unitLabel = options[0].label
        return draft
    }

    static func from(saved: SavedFood) -> DraftMeal {
        from(profile: saved.nutritionProfile)
    }

    static func from(meal: MealEntry) -> DraftMeal {
        var draft = DraftMeal(
            name: meal.name, proteinGrams: meal.proteinGrams, carbsGrams: meal.carbsGrams, fatGrams: meal.fatGrams,
            unitLabel: meal.servingSize, confidence: meal.confidenceScore, fiberGrams: meal.fiberGrams,
            sugarGrams: meal.sugarGrams, sodiumMg: meal.sodiumMg, saturatedFatGrams: meal.saturatedFatGrams,
            baseCalories: meal.calories, photoData: meal.photoData, mealType: meal.mealType, timestamp: meal.timestamp
        )
        draft.editing = meal
        return draft
    }

    static func blank() -> DraftMeal {
        DraftMeal(name: "", proteinGrams: 0, carbsGrams: 0, fatGrams: 0, unitLabel: "serving", confidence: 1)
    }
}

extension ServingOption {
    /// Pulls "40 g" / "250ml" out of a serving description.
    nonisolated static func parseGrams(from text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(?:g|ml)\b"#, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text), let value = Double(text[range]), value > 0 else { return nil }
        return value
    }
}

struct MealDetailView: View {
    let draft: DraftMeal

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var amount = 1.0
    @State private var optionIndex = 0
    @State private var mealType: MealType
    @State private var timestamp: Date
    @State private var proteinGrams: Double
    @State private var carbsGrams: Double
    @State private var fatGrams: Double
    @State private var favoriteSaved = false

    init(draft: DraftMeal) {
        self.draft = draft
        _name = State(initialValue: draft.name)
        _mealType = State(initialValue: draft.mealType)
        _timestamp = State(initialValue: draft.timestamp)
        _proteinGrams = State(initialValue: draft.proteinGrams)
        _carbsGrams = State(initialValue: draft.carbsGrams)
        _fatGrams = State(initialValue: draft.fatGrams)
    }

    private var kcalTotal: Double {
        guard let base = draft.baseCalories else {
            return proteinGrams * 4 + carbsGrams * 4 + fatGrams * 9
        }
        let edited = 4 * (proteinGrams - draft.proteinGrams * factor)
            + 4 * (carbsGrams - draft.carbsGrams * factor)
            + 9 * (fatGrams - draft.fatGrams * factor)
        return max(0, base * factor + edited)
    }

    /// Multiplier from the base unit to what's currently selected.
    private var factor: Double {
        guard !draft.servingOptions.isEmpty else { return amount }
        return amount * draft.servingOptions[optionIndex].grams / draft.servingOptions[0].grams
    }

    private var currentUnitLabel: String {
        draft.servingOptions.isEmpty ? draft.unitLabel : draft.servingOptions[optionIndex].label
    }

    private var amountText: String { amount.formatted(.number.precision(.fractionLength(0...2))) }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, Theme.Spacing.sm)

                header
                mealTypeRow
                servingRow

                VStack(spacing: Theme.Spacing.lg) {
                    macroSlider(label: "Protein", color: .macroProtein, value: $proteinGrams, base: 200)
                    macroSlider(label: "Carbs", color: .macroCarbs, value: $carbsGrams, base: 400)
                    macroSlider(label: "Fat", color: .macroFat, value: $fatGrams, base: 150)
                }

                kcalTotalView
                micronutrients

                saveButton
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.lg)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .onAppear {
            // Editing an entry starts from its stored macros, not a rescaled base.
            if draft.editing != nil { amount = 1 }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let data = draft.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
            TextField("Food name", text: $name)
                .font(.title3)
                .fontWeight(.bold)
            Spacer()
            Button(action: saveFavorite) {
                Image(systemName: favoriteSaved ? "star.fill" : "star")
                    .foregroundStyle(favoriteSaved ? .yellow : .secondary)
                    .frame(width: 30, height: 30)
            }
            .accessibilityLabel(favoriteSaved ? "Saved to favorites" : "Save to favorites")
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

    private var mealTypeRow: some View {
        HStack {
            Picker("Meal", selection: $mealType) {
                ForEach(MealType.allCases) { type in
                    Label(type.title, systemImage: type.systemImage).tag(type)
                }
            }
            .pickerStyle(.menu)
            Spacer()
            DatePicker("Time", selection: $timestamp, in: ...Date().addingTimeInterval(60))
                .labelsHidden()
        }
        .font(.subheadline)
    }

    private var servingRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Serving size")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        guard amount > 0.25 else { return }
                        amount = max(0.25, amount - (amount > 1 ? 1 : 0.25))
                        applyServingScale()
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 28, height: 28)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .accessibilityLabel("Decrease servings")

                    Text("\(amountText) × \(currentUnitLabel)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())

                    Button {
                        amount += amount >= 1 ? 1 : 0.25
                        applyServingScale()
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 28)
                            .background(Color(.tertiarySystemFill), in: Circle())
                    }
                    .accessibilityLabel("Increase servings")
                }
                .foregroundStyle(.primary)
                .buttonStyle(.plain)
            }

            if draft.servingOptions.count > 1 {
                Picker("Unit", selection: $optionIndex) {
                    ForEach(Array(draft.servingOptions.enumerated()), id: \.offset) { index, option in
                        Text(option.label).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: optionIndex) { _, _ in applyServingScale() }
            }
        }
    }

    private func applyServingScale() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            proteinGrams = draft.proteinGrams * factor
            carbsGrams = draft.carbsGrams * factor
            fatGrams = draft.fatGrams * factor
        }
    }

    private func macroSlider(label: String, color: Color, value: Binding<Double>, base: Double) -> some View {
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
            // Scaled servings can exceed the usual ceiling; grow it so the
            // thumb never pins at the end.
            Slider(value: value, in: 0...max(base, value.wrappedValue * 1.25))
                .tint(color)
                .accessibilityLabel("\(label) grams")
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
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var micronutrients: some View {
        let rows: [(String, String)] = [
            ("Fiber", draft.fiberGrams * factor, "g"), ("Sugar", draft.sugarGrams * factor, "g"),
            ("Sodium", draft.sodiumMg * factor, "mg"), ("Sat. fat", draft.saturatedFatGrams * factor, "g"),
        ].filter { $0.1 > 0 }.map { ($0.0, "\(Int($0.1.rounded())) \($0.2)") }
        if !rows.isEmpty {
            HStack {
                ForEach(rows, id: \.0) { row in
                    VStack(spacing: 2) {
                        Text(row.1).font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text(row.0).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.Spacing.sm)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .accessibilityElement(children: .combine)
        }
    }

    private var saveButton: some View {
        Button {
            saveMeal()
        } label: {
            Text(draft.editing == nil ? "Save to Log" : "Update Meal")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(Color.brandPrimary, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var servingDescription: String {
        "\(amountText) × \(currentUnitLabel)"
    }

    private func saveMeal() {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        if let entry = draft.editing {
            entry.name = cleanName
            entry.calories = kcalTotal
            entry.proteinGrams = proteinGrams
            entry.carbsGrams = carbsGrams
            entry.fatGrams = fatGrams
            entry.fiberGrams = draft.fiberGrams * factor
            entry.sugarGrams = draft.sugarGrams * factor
            entry.sodiumMg = draft.sodiumMg * factor
            entry.saturatedFatGrams = draft.saturatedFatGrams * factor
            entry.mealType = mealType
            entry.timestamp = timestamp
            if amount != 1 || optionIndex != 0 { entry.servingSize = servingDescription }
            Tracker.shared.mealSaved(entry, context: modelContext)
        } else {
            let entry = MealEntry(
                name: cleanName, calories: kcalTotal, protein: proteinGrams, carbs: carbsGrams, fat: fatGrams,
                confidence: draft.confidence, servingSize: servingDescription, mealType: mealType, timestamp: timestamp,
                fiber: draft.fiberGrams * factor, sugar: draft.sugarGrams * factor, sodiumMg: draft.sodiumMg * factor,
                saturatedFat: draft.saturatedFatGrams * factor, photoData: draft.photoData
            )
            modelContext.insert(entry)
            Tracker.shared.mealSaved(entry, context: modelContext)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func saveFavorite() {
        guard !favoriteSaved else { return }
        modelContext.insert(SavedFood(
            name: name, calories: kcalTotal, protein: proteinGrams, carbs: carbsGrams, fat: fatGrams,
            servingSize: servingDescription, isFavorite: true, fiber: draft.fiberGrams * factor,
            sugar: draft.sugarGrams * factor, sodiumMg: draft.sodiumMg * factor, saturatedFat: draft.saturatedFatGrams * factor
        ))
        try? modelContext.save()
        favoriteSaved = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
