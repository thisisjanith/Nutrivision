//
//  PersistenceController.swift
//  NutriVision
//

import Foundation
import SwiftData
import os

@MainActor
enum PersistenceController {
    static let schema = Schema([
        MealEntry.self, CachedEstimate.self, WeightEntry.self, WaterEntry.self, SavedFood.self,
    ])

    /// One container for the whole process, shared by the SwiftUI scene and
    /// App Intents (which can run without any view being on screen).
    static let shared: ModelContainer = makeContainer(inMemory: isUITesting)

    /// UI tests launch with `-uiTesting` for an empty in-memory store and no onboarding.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    static func makeContainer(inMemory: Bool, cloudSync: Bool? = nil) -> ModelContainer {
        let cloudSync = cloudSync ?? ProfileStore.shared.profile.iCloudSync
        // CloudKit needs a signed-in iCloud account and the iCloud entitlement;
        // without them container creation would fail, so sync is opt-in and
        // silently falls back to local-only.
        let wantsCloud = cloudSync && !inMemory && FileManager.default.ubiquityIdentityToken != nil
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: wantsCloud ? .automatic : .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            if wantsCloud {
                Log.storage.error("CloudKit container failed (\(error.localizedDescription)); using local store")
                return makeContainer(inMemory: false, cloudSync: false)
            }
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
