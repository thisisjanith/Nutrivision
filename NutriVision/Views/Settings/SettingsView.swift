//
//  SettingsView.swift
//  NutriVision
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealEntry.timestamp) private var meals: [MealEntry]

    @State private var reminders = ReminderService.load()
    @State private var remindersDenied = false
    @State private var healthDenied = false
    @State private var overrideOn = false
    @State private var exportURLs: (csv: URL, pdf: URL)?

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                goalsSection
                remindersSection
                integrationsSection
                exportSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { overrideOn = store.profile.calorieOverride != nil }
            .onDisappear { Tracker.shared.refreshSnapshot(context: modelContext) }
        }
    }

    // MARK: Sections

    private var profileSection: some View {
        Section("Profile") {
            TextField("Name", text: $store.profile.name)
            Picker("Units", selection: $store.profile.units) {
                ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
            }
            Picker("Sex", selection: $store.profile.sex) {
                ForEach(Sex.allCases) { Text($0.title).tag($0) }
            }
            Stepper("Age: \(store.profile.age)", value: $store.profile.age, in: 14...100)
            LabeledContent("Height") {
                TextField("Height", value: heightBinding, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 80)
                Text(store.profile.units == .metric ? "cm" : "in").foregroundStyle(.secondary)
            }
            LabeledContent("Weight") {
                TextField("Weight", value: weightBinding(\.weightKg), format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 80)
                Text(store.profile.units.weightUnit).foregroundStyle(.secondary)
            }
            Picker("Activity", selection: $store.profile.activity) {
                ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    private var goalsSection: some View {
        let goals = store.goals
        return Section {
            Picker("Goal", selection: $store.profile.goal) {
                ForEach(GoalType.allCases) { Text($0.title).tag($0) }
            }
            if store.profile.goal != .maintain {
                LabeledContent("Target weight") {
                    TextField("Target", value: weightBinding(\.targetWeightKg), format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 80)
                    Text(store.profile.units.weightUnit).foregroundStyle(.secondary)
                }
                Picker("Pace", selection: $store.profile.weeklyRateKg) {
                    Text("0.25 kg / week").tag(0.25)
                    Text("0.5 kg / week").tag(0.5)
                    Text("0.75 kg / week").tag(0.75)
                }
            }
            Picker("Diet style", selection: $store.profile.diet) {
                ForEach(DietPreset.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Set calories manually", isOn: $overrideOn)
                .onChange(of: overrideOn) { _, on in
                    store.profile.calorieOverride = on ? (store.profile.calorieOverride ?? goals.calories) : nil
                }
            if overrideOn {
                NumberField(title: "Daily calories", value: Binding(
                    get: { store.profile.calorieOverride ?? goals.calories },
                    set: { store.profile.calorieOverride = max($0, 0) }
                ), unit: "kcal")
            }
            NumberField(title: "Water goal", value: Binding(
                get: { store.waterGoalMl },
                set: { store.profile.waterGoalMl = max($0, 0) }
            ), unit: "ml")
        } header: {
            Text("Goals")
        } footer: {
            Text("Target: \(Int(goals.calories)) kcal · P \(Int(goals.protein)) g · C \(Int(goals.carbs)) g · F \(Int(goals.fat)) g")
        }
    }

    private var remindersSection: some View {
        Section {
            ForEach($reminders) { $reminder in
                HStack {
                    Toggle(reminder.type.title, isOn: $reminder.enabled)
                    if reminder.enabled {
                        DatePicker("Time", selection: timeBinding($reminder), displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
            }
        } header: {
            Text("Meal reminders")
        } footer: {
            if remindersDenied { Text("Notifications are turned off for NutriVision. Enable them in Settings.").foregroundStyle(.red) }
        }
        .onChange(of: reminders) { _, new in
            Task { remindersDenied = !(await ReminderService.apply(new)) }
        }
    }

    private var integrationsSection: some View {
        Section {
            Toggle("Sync with Apple Health", isOn: Binding(
                get: { store.profile.syncToHealth },
                set: { on in
                    if on {
                        Task { healthDenied = !(await Tracker.shared.enableHealthSync()) }
                    } else {
                        store.profile.syncToHealth = false
                    }
                }
            ))
            Toggle("iCloud sync", isOn: $store.profile.iCloudSync)
        } header: {
            Text("Integrations")
        } footer: {
            VStack(alignment: .leading) {
                if healthDenied { Text("Health access wasn't granted. You can change this in the Health app.").foregroundStyle(.red) }
                Text("iCloud sync takes effect the next time the app launches and needs you to be signed in to iCloud.")
            }
        }
    }

    private var exportSection: some View {
        Section("Export") {
            if let urls = exportURLs {
                ShareLink(item: urls.csv) { Label("Share CSV", systemImage: "tablecells") }
                ShareLink(item: urls.pdf) { Label("Share PDF", systemImage: "doc.richtext") }
            } else {
                Button("Prepare export (\(meals.count) meals)", systemImage: "square.and.arrow.up") {
                    if let csv = try? ExportService.writeCSV(meals: meals), let pdf = try? ExportService.writePDF(meals: meals) {
                        exportURLs = (csv, pdf)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            Text("Calorie targets are estimates, not medical advice.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Bindings

    private var heightBinding: Binding<Double> {
        Binding(
            get: { store.profile.units == .metric ? store.profile.heightCm : (store.profile.heightCm / 2.54).rounded() },
            set: { store.profile.heightCm = store.profile.units == .metric ? $0 : $0 * 2.54 }
        )
    }

    private func weightBinding(_ keyPath: WritableKeyPath<UserProfile, Double>) -> Binding<Double> {
        Binding(
            get: { store.profile.units.displayWeight(kg: store.profile[keyPath: keyPath]) },
            set: { store.profile[keyPath: keyPath] = store.profile.units.kilograms(fromDisplay: $0) }
        )
    }

    private func timeBinding(_ reminder: Binding<MealReminder>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: reminder.wrappedValue.hour, minute: reminder.wrappedValue.minute)) ?? Date() },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                reminder.wrappedValue.hour = parts.hour ?? 8
                reminder.wrappedValue.minute = parts.minute ?? 0
            }
        )
    }
}
