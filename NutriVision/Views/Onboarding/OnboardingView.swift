//
//  OnboardingView.swift
//  NutriVision
//

import SwiftUI

/// First-run flow: body stats, activity, goal and diet produce a personal
/// calorie and macro target (Mifflin-St Jeor) in place of a fixed number.
struct OnboardingView: View {
    @Bindable var store: ProfileStore
    var onFinish: () -> Void

    @State private var step = 0
    private let lastStep = 4

    private var profile: Binding<UserProfile> { $store.profile }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(step + 1), total: Double(lastStep + 1))
                .tint(Color.brandPrimary)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.md)
                .accessibilityLabel("Step \(step + 1) of \(lastStep + 1)")

            TabView(selection: $step) {
                welcome.tag(0)
                body(for: 1).tag(1)
                activityStep.tag(2)
                goalStep.tag(3)
                summary.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: step)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(step == lastStep ? "Get Started" : "Continue") {
                    if step == lastStep {
                        store.profile.hasOnboarded = true
                        onFinish()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandPrimary)
                .controlSize(.large)
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private func page<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title).font(.largeTitle.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }
                content()
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private var welcome: some View {
        page("Welcome to NutriVision", subtitle: "Scan food, track nutrition, and get targets built for your body.") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("What should we call you?").font(.headline)
                TextField("Name", text: profile.name)
                    .textContentType(.givenName)
                    .textFieldStyle(.roundedBorder)
                Picker("Units", selection: profile.units) {
                    ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .cardStyle()
        }
    }

    private func body(for _: Int) -> some View {
        page("About you", subtitle: "Used only to estimate how many calories you burn.") {
            VStack(spacing: Theme.Spacing.md) {
                Picker("Sex", selection: profile.sex) {
                    ForEach(Sex.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Stepper("Age: \(store.profile.age)", value: profile.age, in: 14...100)
                HStack {
                    Text("Height")
                    Spacer()
                    TextField("Height", value: heightBinding, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 80)
                    Text(store.profile.units == .metric ? "cm" : "in").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("Weight", value: weightBinding, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 80)
                    Text(store.profile.units.weightUnit).foregroundStyle(.secondary)
                }
            }
            .cardStyle()
        }
    }

    private var activityStep: some View {
        page("How active are you?", subtitle: "Pick what fits a typical week.") {
            VStack(spacing: Theme.Spacing.sm) {
                ForEach(ActivityLevel.allCases) { level in
                    Button {
                        store.profile.activity = level
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(level.title).font(.headline)
                                Text(level.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.profile.activity == level {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.brandPrimary)
                            }
                        }
                        .foregroundStyle(.primary)
                        .cardStyle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(store.profile.activity == level ? .isSelected : [])
                }
            }
        }
    }

    private var goalStep: some View {
        page("Your goal", subtitle: "We'll set a calorie target to match.") {
            VStack(spacing: Theme.Spacing.md) {
                Picker("Goal", selection: profile.goal) {
                    ForEach(GoalType.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if store.profile.goal != .maintain {
                    HStack {
                        Text("Target weight")
                        Spacer()
                        TextField("Target", value: targetBinding, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 80)
                        Text(store.profile.units.weightUnit).foregroundStyle(.secondary)
                    }
                    Picker("Pace", selection: profile.weeklyRateKg) {
                        Text("Gentle (0.25 kg/wk)").tag(0.25)
                        Text("Steady (0.5 kg/wk)").tag(0.5)
                        Text("Fast (0.75 kg/wk)").tag(0.75)
                    }
                }
                Picker("Diet style", selection: profile.diet) {
                    ForEach(DietPreset.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .cardStyle()
        }
    }

    private var summary: some View {
        let goals = NutritionGoals.macroGoals(store.profile)
        return page("Your daily targets", subtitle: "You can change these any time in Settings.") {
            VStack(spacing: Theme.Spacing.md) {
                VStack {
                    Text("\(Int(goals.calories.rounded()))")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.brandPrimary)
                    Text("calories per day").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                HStack {
                    macro("Protein", goals.protein, .macroProtein)
                    macro("Carbs", goals.carbs, .macroCarbs)
                    macro("Fat", goals.fat, .macroFat)
                }
                Text("Based on Mifflin-St Jeor: about \(Int(NutritionGoals.tdee(store.profile).rounded())) kcal to maintain your weight.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .cardStyle()
        }
    }

    private func macro(_ label: String, _ grams: Double, _ color: Color) -> some View {
        VStack {
            Text("\(Int(grams))g").font(.title3.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // Display-unit bindings: the profile always stores cm and kg.

    private var heightBinding: Binding<Double> {
        Binding(
            get: { store.profile.units == .metric ? store.profile.heightCm : (store.profile.heightCm / 2.54).rounded() },
            set: { store.profile.heightCm = store.profile.units == .metric ? $0 : $0 * 2.54 }
        )
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { store.profile.units.displayWeight(kg: store.profile.weightKg) },
            set: { store.profile.weightKg = store.profile.units.kilograms(fromDisplay: $0) }
        )
    }

    private var targetBinding: Binding<Double> {
        Binding(
            get: { store.profile.units.displayWeight(kg: store.profile.targetWeightKg) },
            set: { store.profile.targetWeightKg = store.profile.units.kilograms(fromDisplay: $0) }
        )
    }
}
