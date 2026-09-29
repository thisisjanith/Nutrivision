//
//  CustomFoodEditor.swift
//  NutriVision
//

import SwiftUI
import SwiftData

/// Creates a custom food (macros per serving) or a recipe built from
/// ingredients and divided into servings.
struct CustomFoodEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var servingSize = "1 serving"
    @State private var calories = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var isRecipe = false
    @State private var servings = 1.0
    @State private var ingredients: [RecipeIngredient] = []

    private var recipeTotals: (kcal: Double, p: Double, c: Double, f: Double) {
        let n = max(servings, 1)
        return (ingredients.reduce(0) { $0 + $1.calories } / n, ingredients.reduce(0) { $0 + $1.protein } / n,
                ingredients.reduce(0) { $0 + $1.carbs } / n, ingredients.reduce(0) { $0 + $1.fat } / n)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (isRecipe ? !ingredients.isEmpty : calories > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Toggle("This is a recipe", isOn: $isRecipe.animation())
                }
                if isRecipe {
                    recipeSections
                } else {
                    Section("Per serving") {
                        TextField("Serving size", text: $servingSize)
                        NumberField(title: "Calories", value: $calories, unit: "kcal")
                        NumberField(title: "Protein", value: $protein, unit: "g")
                        NumberField(title: "Carbs", value: $carbs, unit: "g")
                        NumberField(title: "Fat", value: $fat, unit: "g")
                    }
                }
            }
            .navigationTitle(isRecipe ? "New Recipe" : "New Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
        }
    }

    @ViewBuilder
    private var recipeSections: some View {
        Section("Ingredients") {
            ForEach($ingredients) { $ingredient in
                VStack(alignment: .leading) {
                    TextField("Ingredient", text: $ingredient.name)
                    HStack {
                        compact("kcal", $ingredient.calories)
                        compact("P", $ingredient.protein)
                        compact("C", $ingredient.carbs)
                        compact("F", $ingredient.fat)
                    }
                }
            }
            .onDelete { ingredients.remove(atOffsets: $0) }
            Button("Add ingredient", systemImage: "plus") {
                ingredients.append(RecipeIngredient(name: "", calories: 0, protein: 0, carbs: 0, fat: 0))
            }
            Menu("Add from database", systemImage: "magnifyingglass") {
                ForEach(FoodDatabase.shared.foods.prefix(40)) { food in
                    Button(food.name) {
                        let p = food.defaultProfile
                        ingredients.append(RecipeIngredient(name: "\(food.name) (\(p.servingSize))", calories: p.calories,
                                                            protein: p.proteinGrams, carbs: p.carbsGrams, fat: p.fatGrams))
                    }
                }
            }
        }
        Section("Makes") {
            NumberField(title: "Servings", value: $servings)
            let t = recipeTotals
            Text("Per serving: \(Int(t.kcal.rounded())) kcal · P \(Int(t.p.rounded())) · C \(Int(t.c.rounded())) · F \(Int(t.f.rounded()))")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func compact(_ label: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        if isRecipe {
            let t = recipeTotals
            let count = max(servings, 1)
            modelContext.insert(SavedFood(
                name: cleanName, calories: t.kcal, protein: t.p, carbs: t.c, fat: t.f,
                servingSize: count == 1 ? "1 recipe" : "1 of \(count.formatted(.number.precision(.fractionLength(0...1)))) servings",
                isRecipe: true, ingredientsJSON: try? JSONEncoder().encode(ingredients)
            ))
        } else {
            modelContext.insert(SavedFood(name: cleanName, calories: calories, protein: protein, carbs: carbs, fat: fat,
                                          servingSize: servingSize.isEmpty ? "1 serving" : servingSize))
        }
        try? modelContext.save()
        dismiss()
    }
}
