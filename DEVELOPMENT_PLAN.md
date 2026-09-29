# NutriVision — Advanced Development Plan

## Status
All tiers are implemented in code and the app + widget targets build. **Nothing has been run on a simulator or device yet**
(see `SETUP.md` for the manual steps: capabilities, proxy deploy, detector model, watch embedding).
Items marked `[~]` are built but need a real-device check or an external step.

---

## Tier 1: Recognition Pipeline (tiered: deterministic, local, cloud)

### Level 0: Instant deterministic paths (on-device)
- [x] Barcode scan (AVFoundation metadata output) + Open Food Facts lookup, USDA FoodData Central fallback (`FallbackProductLookup`)
- [x] Nutrition label OCR with `VNRecognizeTextRequest` + `NutritionLabelParser` ("Label" button in scanner). Needs tuning against real label photos

### Level 1: Viewfinder intelligence (local edge ML)
- [x] Generic region detector (`FoodRegionDetector`): loads a bundled `FoodDetector` Core ML model if present, otherwise Vision saliency
- [ ] Train and bundle the YOLOv8-nano food/beverage model (steps in `Proxy/README.md`); saliency is the stand-in until then
- [x] `DetectionStabilizer` + box smoothing over detector output, haptic on lock-on, crisp box overlay
- [x] MobileNetV2 removed from the live path (kept as offline fallback after capture)

### Level 2: Semantic engine (cloud vision API)
- [x] Capture -> `ProxyVisionClient` -> strict-schema `CloudFoodEstimate` (name, confidence, calories, macros, hidden-ingredients flag, portion bucket)
- [x] Proxy (`Proxy/worker.js`, Claude Haiku via forced tool call) keeps the API key off-device
- [ ] Deploy the proxy and set `proxyURL` / `proxyToken`; add rate limiting
- [x] SwiftData cache (`CachedEstimate`) keyed by Vision feature print; near-match skips the network. Match threshold (0.3) needs tuning on real photos

### Level 3: Pragmatic portion estimation
- [x] LiDAR distance via `AVCaptureDepthDataOutput` (not ARKit: ARKit would take the camera from the live preview); sent to the proxy as a size hint. Untested on hardware
- [x] Portion buckets from the model (Small, Medium, Large, Cup, Tablespoon, Palm-sized)
- [x] Portion slider (0.25x-3x) under the result scales all macros; flows into Meal Detail

### Deferred (after the above)
- [ ] Learn from user corrections (on-device personalization)
- [ ] Multi-food detection with per-item classification (revisit if Level 2 crops are not enough)

## Tier 2: Nutrition Data
- [x] Bundled database replaces the hardcoded dictionary for search/logging (`FoodDatabase.json`, 131 common foods, USDA-style per-100 g values written from memory: verify or replace with a real FDC export via `Scripts/generate_food_database.py`). The classifier tables (`FoodNutritionMap` + Food-101) still back photo recognition
- [x] Text search and manual entry (`FoodSearchView`)
- [x] Micronutrients: fiber, sugar, sodium, saturated fat on `MealEntry`/`NutritionProfile` (added with defaults, so SwiftData migrates the existing store lightweight; no `VersionedSchema` needed for additive fields)
- [x] Serving units (household servings, grams, ounces) with conversion in `MealDetailView`
- [x] Custom foods and recipes (`CustomFoodEditor`, `SavedFood`)
- [x] Favorites, recents, one-tap re-log
- [x] Meal types (auto-suggested by time of day, grouped on the dashboard)

## Tier 3: Personalization and Goals
- [x] Onboarding with Mifflin-St Jeor TDEE replacing the fixed 1800 kcal (`OnboardingView`, `NutritionGoals`)
- [x] Macro goals and diet presets (balanced, high-protein, low-carb, keto); rings and bars fill toward goals
- [x] Weight tracking with smoothed trend line and goal ETA (`WeightView`)
- [x] Water intake tracking (dashboard card, widget/Siri button)
- [x] Adaptive goals from weight trend vs. intake (`AdaptiveGoal`, needs 14+ days of weights and 10 logged days)

## Tier 4: Apple Platform Integration
- [~] HealthKit: writes energy/macros/water/weight, reads active energy, steps, weight (`HealthService`). Needs the HealthKit capability
- [~] WidgetKit home and lock screen widgets (`NutriVisionWidgets`). Needs the App Group capability to show real data
- [~] Live Activity for the fasting timer (`FastingController`, `FastingLiveActivity`)
- [~] App Intents / Siri / Shortcuts: Log Food, Calories Left, Add Water, Scan Food
- [~] Interactive widget buttons (scan opens the app on the scanner; +250 ml water)
- [~] Apple Watch app (`NutriVisionWatch`): rings, quick log, water. Not embedded in the iPhone app (see `SETUP.md`); source type-checks for watchOS but has not been built as a target on this machine (no watchOS runtime)
- [~] iCloud sync via SwiftData + CloudKit (Settings toggle, applies on relaunch, falls back to local). Needs iCloud/CloudKit capability
- [x] Local notification meal reminders (`ReminderService`)

## Tier 5: Insights and Analytics
- [x] Weekly/monthly Swift Charts for calories (with goal line) and macros; weight chart in `WeightView`
- [x] Streaks and consistency score
- [x] On-device insight cards (protein below goal, over calories, low fiber, high sodium, water)
- [x] CSV and PDF export (Insights menu and Settings)

## Tier 6: UX Polish
- [x] Haptics on lock-on, capture result, portion slider, water, save
- [x] Scan from photo library (`PhotosPicker`)
- [x] Meal photo thumbnail per entry (`@Attribute(.externalStorage)`), shown in lists
- [x] Undo after delete (History); edit past meals (tap a row)
- [x] Accessibility: labels/values on rings, bars and charts. A full VoiceOver + Dynamic Type pass on device is still worth doing
- [x] Localization: String Catalog with Spanish (`Localizable.xcstrings`, ~110 strings) and metric/imperial units. Only strings in the catalog are translated
- [x] Empty states, camera-permission-denied screen with Settings link, torch toggle

## Tier 7: Engineering Quality
- [x] Protocol-based DI: `FoodClassifying`, `NutritionSource`, `ProductLookup`, `VisionLLMClient`, `FoodRegionDetector`, `HealthStoring`
- [x] View model tests (Dashboard totals, History filtering, goal math, scanner pipeline with stubs)
- [~] UI tests for the logging flow written (`LoggingFlowUITests`, launch arg `-uiTesting`). Render smoke tests instead of pixel snapshots (no third-party snapshot library). None of the new tests have been run
- [~] Instruments: `os_signpost` interval around per-frame detection; profiling itself must be done on a device
- [x] Model evaluation harness (`ModelEvaluator`, `NUTRIVISION_EVAL_DIR`)
- [x] CI: `.github/workflows/ci.yml` runs `xcodebuild test` (check the runner/Xcode version)
- [x] `os.Logger` categories and MetricKit crash/hang diagnostics (no third-party SDK)
- [x] Privacy manifest (`PrivacyInfo.xcprivacy`) for app and widget. Review the declared data types before submitting
