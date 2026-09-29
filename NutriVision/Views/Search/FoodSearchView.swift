//
//  FoodSearchView.swift
//  NutriVision
//
//  Text search over the bundled database plus favourites, custom foods and
//  recents, with one-tap re-log.
//

import SwiftUI
import SwiftData

struct FoodSearchView: View {
    /// Called with a draft to review in the meal detail sheet.
    var onSelect: (DraftMeal) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedFood.createdAt, order: .reverse) private var savedFoods: [SavedFood]
    @Query private var recentMeals: [MealEntry]

    @State private var query = ""
    @State private var showEditor = false
    @State private var loggedName: String?

    init(onSelect: @escaping (DraftMeal) -> Void) {
        self.onSelect = onSelect
        var descriptor = FetchDescriptor<MealEntry>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 80
        _recentMeals = Query(descriptor)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var favorites: [SavedFood] { savedFoods.filter(\.isFavorite) }
    private var customFoods: [SavedFood] { savedFoods.filter { !$0.isFavorite } }

    /// Distinct recent meals, newest first.
    private var recents: [MealEntry] {
        var seen = Set<String>()
        return recentMeals.filter { seen.insert($0.name.lowercased()).inserted }.prefix(12).map { $0 }
    }

    private var matchingSaved: [SavedFood] {
        savedFoods.filter { $0.name.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    private var databaseResults: [FoodRecord] {
        FoodDatabase.shared.search(trimmedQuery)
    }

    var body: some View {
        NavigationStack {
            List {
                if trimmedQuery.isEmpty {
                    idleSections
                } else {
                    resultSections
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Enter manually", systemImage: "square.and.pencil") { onSelect(.blank()); dismiss() }
                        Button("Create food or recipe", systemImage: "plus.circle") { showEditor = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("More ways to add")
                }
            }
            .sheet(isPresented: $showEditor) { CustomFoodEditor() }
            .overlay(alignment: .bottom) {
                if let loggedName {
                    Label("Logged \(loggedName)", systemImage: "checkmark.circle.fill")
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(.ultraThickMaterial, in: Capsule())
                        .padding(.bottom, Theme.Spacing.md)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: loggedName)
        }
    }

    @ViewBuilder
    private var idleSections: some View {
        if favorites.isEmpty && customFoods.isEmpty && recents.isEmpty {
            ContentUnavailableView("Search for a food", systemImage: "magnifyingglass",
                                   description: Text("Type a food name, or enter one manually with the + button."))
                .listRowBackground(Color.clear)
        }
        if !favorites.isEmpty {
            Section("Favorites") {
                ForEach(favorites) { saved in savedRow(saved) }
            }
        }
        if !customFoods.isEmpty {
            Section("My Foods & Recipes") {
                ForEach(customFoods) { saved in savedRow(saved) }
            }
        }
        if !recents.isEmpty {
            Section("Recent") {
                ForEach(recents) { meal in
                    row(title: meal.name, subtitle: "\(Int(meal.calories.rounded())) kcal · \(meal.servingSize)",
                        open: { onSelect(.from(profile: profile(of: meal))); dismiss() },
                        quickLog: { relog(meal) })
                }
            }
        }
    }

    @ViewBuilder
    private var resultSections: some View {
        let saved = matchingSaved
        let results = databaseResults
        if !saved.isEmpty {
            Section("Your Foods") {
                ForEach(saved) { food in savedRow(food) }
            }
        }
        if !results.isEmpty {
            Section("Database") {
                ForEach(results) { food in
                    let profile = food.defaultProfile
                    row(title: food.name, subtitle: "\(Int(profile.calories.rounded())) kcal · \(profile.servingSize)",
                        open: { onSelect(.from(food: food)); dismiss() },
                        quickLog: { log(profile) })
                }
            }
        }
        if saved.isEmpty && results.isEmpty {
            ContentUnavailableView {
                Label("No results", systemImage: "questionmark.circle")
            } description: {
                Text("Nothing matches \"\(trimmedQuery)\".")
            } actions: {
                Button("Enter \"\(trimmedQuery)\" manually") {
                    var draft = DraftMeal.blank()
                    draft.name = trimmedQuery
                    onSelect(draft)
                    dismiss()
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    private func savedRow(_ saved: SavedFood) -> some View {
        row(title: saved.name, subtitle: "\(Int(saved.calories.rounded())) kcal · \(saved.servingSize)",
            systemImage: saved.isRecipe ? "book.closed" : (saved.isFavorite ? "star.fill" : "fork.knife"),
            open: { onSelect(.from(saved: saved)); dismiss() },
            quickLog: { log(saved.nutritionProfile) })
            .swipeActions {
                Button(role: .destructive) {
                    modelContext.delete(saved)
                    try? modelContext.save()
                } label: { Label("Delete", systemImage: "trash") }
            }
    }

    private func row(title: String, subtitle: String, systemImage: String = "fork.knife",
                     open: @escaping () -> Void, quickLog: @escaping () -> Void) -> some View {
        HStack {
            Button(action: open) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: systemImage).foregroundStyle(Color.brandPrimary).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            Button(action: quickLog) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Color.brandPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log \(title) now")
        }
    }

    // MARK: Actions

    /// Recents reopen as a fresh draft, never as an edit of the old entry.
    private func profile(of meal: MealEntry) -> NutritionProfile {
        NutritionProfile(displayName: meal.name, calories: meal.calories, proteinGrams: meal.proteinGrams,
                         carbsGrams: meal.carbsGrams, fatGrams: meal.fatGrams, servingSize: meal.servingSize,
                         fiberGrams: meal.fiberGrams, sugarGrams: meal.sugarGrams, sodiumMg: meal.sodiumMg,
                         saturatedFatGrams: meal.saturatedFatGrams)
    }

    private func relog(_ meal: MealEntry) {
        let entry = MealEntry(name: meal.name, calories: meal.calories, protein: meal.proteinGrams, carbs: meal.carbsGrams,
                              fat: meal.fatGrams, servingSize: meal.servingSize, fiber: meal.fiberGrams, sugar: meal.sugarGrams,
                              sodiumMg: meal.sodiumMg, saturatedFat: meal.saturatedFatGrams, photoData: meal.photoData)
        save(entry)
    }

    private func log(_ profile: NutritionProfile) {
        save(MealEntry(name: profile.displayName, calories: profile.calories, protein: profile.proteinGrams,
                       carbs: profile.carbsGrams, fat: profile.fatGrams, servingSize: profile.servingSize,
                       fiber: profile.fiberGrams, sugar: profile.sugarGrams, sodiumMg: profile.sodiumMg,
                       saturatedFat: profile.saturatedFatGrams))
    }

    private func save(_ entry: MealEntry) {
        modelContext.insert(entry)
        Tracker.shared.mealSaved(entry, context: modelContext)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        loggedName = entry.name
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            loggedName = nil
        }
    }
}
