//
//  ContentView.swift
//  NutriVision
//

import SwiftUI
import SwiftData

enum AppTab {
    case dashboard, scan, history, insights
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: AppTab = .dashboard
    @State private var mealDetailDraft: DraftMeal?
    @State private var showFoodSearch = false
    @State private var pendingDraft: DraftMeal?
    @State private var showSettings = false
    @State private var profileStore = ProfileStore.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(
                onAddFood: { showFoodSearch = true },
                onOpenSettings: { showSettings = true },
                onEdit: { mealDetailDraft = .from(meal: $0) }
            )
            .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
            .tag(AppTab.dashboard)

            ScannerView(
                onClose: { selectedTab = .dashboard },
                onConfirm: { detection in
                    mealDetailDraft = DraftMeal.from(detection: detection)
                    selectedTab = .dashboard
                }
            )
            .tabItem { Label("Scan", systemImage: "camera.fill") }
            .tag(AppTab.scan)

            MealHistoryView(onEdit: { mealDetailDraft = .from(meal: $0) })
                .tabItem { Label("History", systemImage: "clock.fill") }
                .tag(AppTab.history)

            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.insights)
        }
        .tint(.brandPrimary)
        .sheet(item: $mealDetailDraft) { draft in
            MealDetailView(draft: draft)
        }
        .sheet(isPresented: $showFoodSearch, onDismiss: {
            if let draft = pendingDraft {
                pendingDraft = nil
                mealDetailDraft = draft
            }
        }) {
            FoodSearchView { pendingDraft = $0 }
        }
        .sheet(isPresented: $showSettings) { SettingsView(store: profileStore) }
        .fullScreenCover(isPresented: Binding(
            get: { !profileStore.profile.hasOnboarded },
            set: { _ in }
        )) {
            OnboardingView(store: profileStore) {
                Tracker.shared.refreshSnapshot(context: modelContext)
            }
        }
        .task {
            drainExternalActions()
            Tracker.shared.refreshSnapshot(context: modelContext)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { drainExternalActions() }
        }
    }

    /// Applies things done outside the app process: a widget button that
    /// asked for the scanner, and water logged from a widget or Siri.
    private func drainExternalActions() {
        if PendingRoute.take() == "scan" { selectedTab = .scan }
        let water = PendingWater.take()
        if water > 0 { Tracker.shared.addWater(milliliters: water, context: modelContext) }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [MealEntry.self, CachedEstimate.self, WeightEntry.self, WaterEntry.self, SavedFood.self], inMemory: true)
}
