//
//  ContentView.swift
//  NutriVision
//

import SwiftUI
import SwiftData

enum AppTab: CaseIterable {
    case dashboard, history, scan, insights, profile

    var title: String {
        switch self {
        case .dashboard: "Home"
        case .history: "History"
        case .scan: "Scan"
        case .insights: "Insights"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "house.fill"
        case .history: "clock.fill"
        case .scan: "viewfinder"
        case .insights: "chart.bar.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: AppTab = .dashboard
    @State private var showScanner = false
    @State private var mealDetailDraft: DraftMeal?
    @State private var showFoodSearch = false
    @State private var pendingDraft: DraftMeal?
    @State private var scannedDraft: DraftMeal?
    @State private var profileStore = ProfileStore.shared

    /// Selecting the middle "Scan" tab opens the scanner and snaps back to the
    /// previous tab, so it behaves like a button inside the native tab bar.
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == .scan {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showScanner = true
                } else {
                    selectedTab = newValue
                }
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            tabPage {
                DashboardView(
                    onAddFood: { showFoodSearch = true },
                    onScan: { showScanner = true },
                    onEdit: { mealDetailDraft = .from(meal: $0) }
                )
            }
            .tabItem { Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.systemImage) }
            .tag(AppTab.dashboard)

            tabPage { MealHistoryView(onEdit: { mealDetailDraft = .from(meal: $0) }) }
                .tabItem { Label(AppTab.history.title, systemImage: AppTab.history.systemImage) }
                .tag(AppTab.history)

            Color.clear
                .tabItem { Label(AppTab.scan.title, systemImage: AppTab.scan.systemImage) }
                .tag(AppTab.scan)

            tabPage { InsightsView() }
                .tabItem { Label(AppTab.insights.title, systemImage: AppTab.insights.systemImage) }
                .tag(AppTab.insights)

            tabPage { SettingsView(store: profileStore, embedded: true) }
                .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage) }
                .tag(AppTab.profile)
        }
        .tint(.brandPrimary)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showScanner, onDismiss: {
            if let draft = scannedDraft {
                scannedDraft = nil
                mealDetailDraft = draft
            }
        }) {
            ScannerView(
                onClose: { showScanner = false },
                onConfirm: { detection in
                    // Presented from onDismiss below: a sheet that starts while the
                    // cover is still leaving ends up with a dead drag gesture.
                    scannedDraft = DraftMeal.from(detection: detection)
                    selectedTab = .dashboard
                    showScanner = false
                }
            )
            .preferredColorScheme(.dark)
        }
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
        if PendingRoute.take() == "scan" { showScanner = true }
        let water = PendingWater.take()
        if water > 0 { Tracker.shared.addWater(milliliters: water, context: modelContext) }
    }
}

private extension ContentView {
    func tabPage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            AppBackground()
            content()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [MealEntry.self, CachedEstimate.self, WeightEntry.self, WaterEntry.self, SavedFood.self], inMemory: true)
}
