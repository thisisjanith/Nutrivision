//
//  ContentView.swift
//  NutriVision
//

import SwiftUI
import SwiftData

enum AppTab {
    case dashboard, scan, history
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .dashboard
    @State private var mealDetailDraft: DraftMeal?

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
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

            MealHistoryView()
                .tabItem { Label("History", systemImage: "clock.fill") }
                .tag(AppTab.history)
        }
        .tint(.brandPrimary)
        .sheet(item: $mealDetailDraft) { draft in
            MealDetailView(draft: draft)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [MealEntry.self, CachedEstimate.self], inMemory: true)
}
