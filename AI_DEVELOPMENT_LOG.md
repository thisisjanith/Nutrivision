# AI Development Log

## 2026-09-08: Project Scaffolding, Data Model & ML Pipeline
- **Prompt:** "Read NutriVision_Claude_Code_Prompt.md alongside the mockup and start building."
- **AI Contribution:** Restructured the default Xcode SwiftData template into the
  `App/Models/ML/ViewModels/Views/Utilities` layout, downloaded `MobileNetV2.mlmodel`
  from Apple's Core ML model gallery, defined `MealEntry` (`@Model`), `Theme.swift`
  design tokens matched to the mockup's hex values, `ClassifierService` (actor
  wrapping `VNCoreMLRequest`), and `FoodNutritionMap` (ImageNet label → nutrition
  lookup table).
- **Developer Review & Adjustments:** Set `IPHONEOS_DEPLOYMENT_TARGET` to 17.0
  (template defaulted to a much higher simulator-only value) and added
  `NSCameraUsageDescription`. Fixed a real actor-isolation bug: the generated
  `MobileNetV2` class inherits the target's `MainActor` default isolation, so
  calling its initializer synchronously inside `ClassifierService`'s `actor`
  `init()` produced a compiler warning for an invalid cross-actor call. Reworked
  model loading to happen lazily on first `classify(image:)` call via
  `MainActor.run`, resolving the warning without weakening the actor boundary.

## 2026-09-08: Scanner, Dashboard, Meal Detail & History Screens
- **Prompt:** Section 3 screen specs (CoreML Vision Scanner, Daily Intake
  Dashboard, Meal Detail & Logging, History & Analytics) from
  `NutriVision_Claude_Code_Prompt.md`, built in the order: Scanner → Dashboard →
  Meal Detail sheet → History.
- **AI Contribution:** Generated `ScannerViewModel` (`@Observable`, `NSObject`
  subclass conforming to `AVCaptureVideoDataOutputSampleBufferDelegate`) with a
  throttled live-classification loop, `ScannerView` with the dashed bounding box
  overlay and translucent detection sheet, `MacroRingView` (three
  `Shape`/`trim(from:to:)` rings with spring animation), `DashboardView` with a
  `@Query`-filtered "today" meal list, `MealDetailView` as a `.sheet` with live
  4/4/9 kcal recalculation from three macro sliders, and `MealHistoryView` using
  Swift Charts `SectorMark` for the donut chart with Week/Month filtering and
  native swipe-to-delete.
- **Developer Review & Adjustments:** Marked `ScannerViewModel.captureOutput`
  `nonisolated` (AVFoundation invokes it off the main actor) and hopped to
  `@MainActor` via `Task` before touching any observable state, to avoid an
  actor-isolation crash rather than just silencing the warning. Wired
  cross-tab navigation (Scanner confirm → Meal Detail sheet presented over
  Dashboard) through `ContentView`'s root `TabView` state rather than adding a
  separate navigation coordinator, since the sheet only needs to be reachable
  from one place.

## 2026-09-08: Root Navigation & Unit Tests
- **Prompt:** "Wire up ContentView.swift with the root TabView... Write unit
  tests for MealEntry macro/kcal calculations and the nutrient mapping logic
  in FoodNutritionMap."
- **AI Contribution:** Built the root `TabView` (Dashboard, Scan, History) with
  `.sheet(item:)` for Meal Detail, and added `MealEntryTests`,
  `FoodNutritionMapTests`, and `ClassificationToNutritionMappingTests` covering
  the 4/4/9 kcal formula, the low-confidence threshold boundary, case-insensitive
  and ImageNet-synonym label matching, and a mocked classification-to-nutrition
  mapping (no live Vision/CoreML call in the test).
- **Developer Review & Adjustments:** None required — build and test suite
  passed on first run after the ClassifierService fix above.

## 2026-09-13: Scanner Inference Pipeline Overhaul
- **Prompt:** "Make this app extremely advanced" → agreed first step was the
  live-scanner inference path, which capped everything downstream.
- **AI Contribution:** Rewrote `ClassifierService` to accept a `CVPixelBuffer`
  directly via `VNImageRequestHandler(cvPixelBuffer:orientation:)` and to return
  the top 5 ranked results instead of one; the Vision request is now built once
  and reused, and `MLModelConfiguration.computeUnits` is set to `.all` so the
  Neural Engine takes the per-frame work. Extracted camera plumbing into
  `Camera/FrameSampler.swift` (interval throttle plus in-flight backpressure,
  all state confined to the capture queue) and added `ML/DetectionStabilizer.swift`
  (rolling-window majority vote over recent frames, mean confidence). Reshaped
  `DetectedFood` around a `FoodCandidate` so the scanner sheet can offer the
  runners-up as one-tap corrections.
- **Developer Review & Adjustments:** The old path did
  `CVPixelBuffer → CIImage → CGImage → UIImage` on every sampled frame purely so
  Vision could convert it back — two full-frame copies per inference, which is
  why the interval had to be as slow as 0.7s; removing it allowed 0.2s. Caught
  that the previous code only guarded on elapsed time, so a slow inference on a
  cold Neural Engine could queue frames faster than they drained — added the
  in-flight guard. Found and fixed a genuine correctness bug in
  `FoodNutritionMap.lookup`: it iterated `profiles` (a `Dictionary`, whose order
  is unspecified) doing substring `contains`, so an ambiguous label could resolve
  to a *different* food between launches, and "corn" matched "popcorn". Replaced
  with per-synonym exact matching, then whole-word-sequence matching over keys
  sorted longest-first. Verified `MobileNetV2`'s `MainActor`-isolated initializer
  still needs the `MainActor.run` hop, and annotated the new `SendablePixelBuffer`
  and `FrameSampler` `nonisolated` so Xcode 26's default-actor-isolation
  inference didn't silently main-actor-isolate the capture path — the build is
  now clean of concurrency warnings rather than merely compiling.
