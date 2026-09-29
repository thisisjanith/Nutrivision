# NutriVision — Claude Code Implementation Guide

Paste this file's contents into Claude Code as the project brief (or save it as
`CLAUDE.md` in the repo root so it's read automatically every session). Attach
`NutriVision_iOS_mockups.pdf` alongside it — the specs below reference exact
values from that file so there's no guessing on colors, copy, or numbers.

---

## 0. Project Setup

Create a new Xcode project:
- **Name:** NutriVision
- **Interface:** SwiftUI
- **Language:** Swift
- **Storage:** SwiftData
- **Minimum target:** iOS 17.0
- **Testing:** include a unit test target (NutriVisionTests)

Download `MobileNetV2.mlmodel` from Apple's Core ML model gallery
(developer.apple.com/machine-learning/models) and drag it into the project
navigator with "Copy items if needed" checked.

---

## 1. Architecture Rules (follow for every file generated)

- **Pattern:** MVVM, Swift 6 concurrency, `@Observable` view models (not
  `ObservableObject`/`@Published`).
- **Persistence:** SwiftData only, via `@Model` and `@Query`. No Core Data.
- **ML:** Vision framework (`VNCoreMLRequest`) wrapping `MobileNetV2`, run
  inside an `actor` for thread safety.
- **Navigation:** `TabView` with 3 tabs (Dashboard, Scan, History) at the
  root; `NavigationStack` inside tabs that need push navigation; the Meal
  Detail screen is a `.sheet` presented over Dashboard, not a tab.
- **Styling:** all colors/spacing pulled from the design tokens in section 2
  — no hardcoded hex values inside views. Support Dark Mode and Dynamic Type
  everywhere.
- **File layout:** use the structure in section 8. Don't flatten it.

---

## 2. Design Tokens (from mockup)

Create `Utilities/Theme.swift` with these first, before building any screen.

```swift
extension Color {
    static let macroProtein = Color(hex: "E8556F") // red/pink
    static let macroCarbs   = Color(hex: "F2A93B") // amber
    static let macroFat     = Color(hex: "3B82D9") // blue
    static let brandPrimary = Color(hex: "1FA37A") // green/teal (goal bar, buttons, active tab)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
}
```

- Rings/macro colors are fixed: **protein = red/pink, carbs = amber, fat = blue.**
  Use these consistently across the Dashboard ring, History donut, and the
  Meal Detail sliders — don't reassign colors per screen.
- Primary accent (goal progress bar, "Save to Log" button, active tab icon,
  scanner confirm button) is a green/teal — use `brandPrimary`.
- Cards use rounded corners, subtle elevation, light gray/system background
  fill, consistent with iOS grouped list styling.
- Add a `Color(hex:)` convenience initializer if the project doesn't already
  have one.

---

## 3. Screen Specs

Build in this order: **Scanner → Dashboard → Meal Detail sheet → History.**
(Scanner first because it's the highest-risk piece — see rationale in prior
planning notes: it's the one part of the app that can't be faked with
placeholder data, and camera/ML issues surface early this way.)

### 3.1 CoreML Vision Scanner (Tab 2, `ScannerView.swift`)

- Full-bleed live camera preview (`AVCaptureSession`) as the background —
  this screen must run on a physical device, not the simulator.
- Overlay: dashed green bounding box in the center of frame with a floating
  label above it showing `"<Food> — <confidence>%"` (e.g. `"Apple — 92%"`),
  updated live as `ClassifierService` returns results.
- Top bar: `X` close button (top-left) to dismiss back to Dashboard, and a
  circular toggle button (top-right) to switch between live camera and photo
  picker.
- Bottom: a translucent bottom sheet peeking up (~25% of screen height) with
  a drag handle, showing:
  - `"DETECTED"` label (small caps, muted)
  - Food name, large and bold (e.g. `"Apple"`)
  - Subtext: `"<calories> kcal · <serving size>"` (e.g. `"95 kcal · 1 medium"`)
  - `"Retake"` text button
  - Circular green checkmark confirm button, bottom-right of the sheet —
    tapping it navigates to Meal Detail & Logging with the detected food
    pre-filled.

### 3.2 Daily Intake Dashboard (Tab 1, `DashboardView.swift`)

- Header: `"Good morning, <name>"` + full date below it in muted text (e.g.
  `"Monday, September 8"`). Name should come from a user profile/settings
  value, not be hardcoded — default to a placeholder if none is set.
- Card containing:
  - `MacroRingView` — 3 concentric rings (protein outer, carbs middle, fat
    inner, or similar layering) built with `Shape` + `trim(from:to:)`, each
    animated with a spring animation when values change. Center of the rings
    shows total kcal large and bold with `"KCAL TODAY"` label beneath in small
    caps.
  - Below the rings: a legend row with colored dots — `Protein 112g`,
    `Carbs 140g`, `Fat 42g` (values pulled from the day's logged meals, not
    hardcoded — these are just the example values from the mockup).
- Calorie goal bar: label `"Calorie Goal"` on the left, `"<consumed> /
  <goal> kcal"` on the right, with a slim green progress bar beneath scaled
  to consumed/goal.
- `"Today's Meals"` section header, followed by a scrollable list of meal
  rows. Each row: circular food thumbnail/icon placeholder, meal name bold,
  time in muted text beneath, calorie count right-aligned (e.g. `Greek
  Yogurt Bowl · 8:15 AM · 320 kcal`).
- Bottom: native `TabView` bar, 3 tabs — Dashboard (grid icon), Scan (camera
  icon), History (clock icon). Active tab tinted with `brandPrimary`.
- **Must support a dark mode variant** using the same layout — verify
  contrast on the rings and card background.

### 3.3 Meal Detail & Logging (`.sheet`, `MealDetailView.swift`)

- Presented as a bottom sheet over Dashboard (background dimmed/blurred),
  rounded top corners, drag handle at top.
- Header row: meal name (e.g. `"Grilled Chicken Salad"`) bold on the left,
  `X` dismiss button on the right.
- Serving size row: label `"Serving size"` left-aligned, stepper control
  right-aligned showing `"1 bowl (250g)"` with `−`/`+` buttons.
- Three labeled sliders, each with the macro's assigned color and a live
  numeric gram value that updates as the slider moves:
  - Protein — e.g. `28g`
  - Carbs — e.g. `45g`
  - Fat — e.g. `12g`
- Below sliders: large centered `"<kcal> kcal total"` that recalculates live
  from the three slider values (use a standard 4/4/9 kcal-per-gram formula
  for protein/carbs/fat).
- Full-width, rounded, green `"Save to Log"` button pinned to the bottom —
  writes a new `MealEntry` to SwiftData and dismisses back to Dashboard.

### 3.4 History & Analytics (Tab 3, `MealHistoryView.swift`)

- Header: `"History"` large title.
- Segmented control: `Week` / `Month`, filters the data below.
- Donut chart card (Swift Charts, `SectorMark`): center shows the range
  label + total kcal (e.g. `"kcal 1,620"`); legend to the right lists
  `Protein 32%`, `Carbs 45%`, `Fat 23%` with matching colored dots. Values
  are computed from logged meals in the selected range, not hardcoded.
- Below the chart: a grouped list of past meals under date section headers
  (`TODAY`, `YESTERDAY`, etc. — small caps, muted).
  - Each row: food thumbnail, name bold, time beneath, kcal right-aligned.
  - Support swipe-to-delete: swiping a row left reveals a red `Delete`
    action that removes the `MealEntry` from SwiftData.
- Bottom: same `TabView` bar as Dashboard, History tab active/tinted.

---

## 4. Data Model

`Models/MealEntry.swift`

```swift
import Foundation
import SwiftData

@Model
final class MealEntry {
    var id: UUID
    var name: String
    var timestamp: Date
    var calories: Double
    var proteinGrams: Double
    var carbsGrams: Double
    var fatGrams: Double
    var confidenceScore: Double
    var servingSize: String

    init(name: String, calories: Double, protein: Double, carbs: Double,
         fat: Double, confidence: Double = 1.0, servingSize: String = "1 serving") {
        self.id = UUID()
        self.name = name
        self.timestamp = Date()
        self.calories = calories
        self.proteinGrams = protein
        self.carbsGrams = carbs
        self.fatGrams = fat
        self.confidenceScore = confidence
        self.servingSize = servingSize
    }
}
```

---

## 5. ML Service

`ML/ClassifierService.swift`

```swift
import Vision
import CoreML
import UIKit

actor ClassifierService {
    private var visionModel: VNCoreMLModel?

    init() {
        if let coreMLModel = try? MobileNetV2(configuration: .init()).model {
            self.visionModel = try? VNCoreMLModel(for: coreMLModel)
        }
    }

    func classify(image: UIImage) async throws -> (label: String, confidence: Float)? {
        guard let cgImage = image.cgImage, let model = visionModel else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let results = request.results as? [VNClassificationObservation],
                      let topResult = results.first else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (label: topResult.identifier, confidence: topResult.confidence))
            }
            request.imageCropAndScaleOption = .centerCrop
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}
```

Also create `ML/FoodNutritionMap.swift` — a static lookup mapping common
ImageNet food labels (apple, banana, pizza, salad, sandwich, etc.) to
approximate calorie/macro profiles, since MobileNetV2 returns raw class
labels, not nutrition data. Flag classifications under ~60% confidence as
low-confidence in the UI rather than auto-filling.

---

## 6. Prompt Sequence to Run in Claude Code

Run these one at a time, inspecting the git diff after each before moving on:

1. `"Set up the SwiftData ModelContainer in NutriVisionApp.swift and confirm MealEntry persists correctly with a quick preview test."`
2. `"Implement ClassifierService and FoodNutritionMap as specified in this file. Write a unit test that mocks a UIImage classification and asserts a mapped nutrition result."`
3. `"Build ScannerViewModel using @Observable. It should manage AVCaptureSession state, call ClassifierService on captured frames, and expose the current detection (label, confidence, mapped nutrition) to ScannerView."`
4. `"Build ScannerView matching section 3.1 of NutriVision_Claude_Code_Prompt.md exactly — camera preview, bounding box overlay, bottom detection sheet, confirm button."`
5. `"Build MacroRingView as a reusable custom SwiftUI component using Shape + trim(from:to:) with spring animation, per section 3.2. Support Dynamic Type and Dark Mode."`
6. `"Build DashboardView per section 3.2, using MacroRingView and @Query on MealEntry filtered to today."`
7. `"Build MealDetailView as a .sheet per section 3.3, with live kcal recalculation from the three sliders."`
8. `"Build MealHistoryView per section 3.4 using Swift Charts SectorMark for the donut chart, with Week/Month filtering and swipe-to-delete."`
9. `"Wire up ContentView.swift with the root TabView (Dashboard, Scan, History) and NavigationStack where needed."`
10. `"Write unit tests for MealEntry macro/kcal calculations and the nutrient mapping logic in FoodNutritionMap."`

---

## 7. AI Development Log

Create `AI_DEVELOPMENT_LOG.md` at the repo root (required by the assignment's
AI-assisted development documentation rule). Add an entry after each session,
in this format:

```markdown
## 2026-09-08: CoreML Pipeline & Model Integration
- **Prompt:** "Configure ClassifierService using Vision VNCoreMLRequest for MobileNetV2 with async/await."
- **AI Contribution:** Generated thread-safe actor pattern and Swift concurrency wrapper around Vision callbacks.
- **Developer Review & Adjustments:** Fixed error handling for low-confidence classifications (<60%) and mapped raw ImageNet strings to user-friendly food categories.
```

---

## 8. Project Layout

```
NutriVision/
├── App/
│   └── NutriVisionApp.swift
├── Models/
│   └── MealEntry.swift
├── ML/
│   ├── MobileNetV2.mlmodel
│   ├── ClassifierService.swift
│   └── FoodNutritionMap.swift
├── ViewModels/
│   ├── DashboardViewModel.swift
│   └── ScannerViewModel.swift
├── Views/
│   ├── ContentView.swift
│   ├── Dashboard/
│   │   ├── DashboardView.swift
│   │   └── Components/MacroRingView.swift
│   ├── Scanner/
│   │   └── ScannerView.swift
│   ├── MealDetail/
│   │   └── MealDetailView.swift
│   └── History/
│       └── MealHistoryView.swift
└── Utilities/
    ├── Theme.swift
    └── Modifiers/CardStyleModifier.swift
```

---

## 9. Build Verification

After each modification, run:

```
xcodebuild -scheme NutriVision -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Note: the Scanner screen's `AVCaptureSession` cannot be exercised on the
simulator — verify camera behavior on a physical device before the demo.
