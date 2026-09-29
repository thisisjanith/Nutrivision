# NutriVision — Advanced Development Plan

## Current State
- Scanner pipeline is solid: Neural Engine inference, frame backpressure, `DetectionStabilizer` (rolling majority vote), top-5 corrections.
- **Main limit:** MobileNetV2 is a general ImageNet model. Only ~39 foods map to hardcoded nutrition values, it recognises one item per frame, and it does not estimate portion size.

## Suggested Order
1. Tier 1 Levels 0-1: barcode (in progress), label OCR, generic food detector
2. Tier 1 Levels 2-3: Vision LLM + cache, portion buckets and slider
3. Tier 3 onboarding and goals, Tier 4 HealthKit
4. Widgets, App Intents, iCloud sync
5. Insights, polish and CI alongside everything else

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
- [ ] Replace hardcoded dictionary in `FoodNutritionMap.swift` with a bundled database (USDA FoodData Central subset, SQLite/JSON)
- [ ] Text search and manual entry
- [ ] Micronutrients: fiber, sugar, sodium, saturated fat, key vitamins (extend `MealEntry` with a SwiftData `VersionedSchema` migration)
- [ ] Serving units (grams, cups, pieces) with conversions
- [ ] Custom foods and recipes
- [ ] Favorites, recents, one-tap re-log
- [ ] Meal types (breakfast, lunch, dinner, snack)

## Tier 3: Personalization and Goals
- [ ] Onboarding (age, sex, height, weight, activity) with Mifflin-St Jeor TDEE instead of fixed 1800 kcal (`DashboardViewModel.swift:30`)
- [ ] Macro goals (grams or %) and diet presets (keto, high-protein, balanced)
- [ ] Weight tracking with trend line and goal ETA
- [ ] Water intake tracking
- [ ] Adaptive goals based on weight trend vs. intake

## Tier 4: Apple Platform Integration
- [ ] HealthKit: write dietary energy/macros; read active energy, weight, steps
- [ ] WidgetKit home/lock screen widgets
- [ ] Live Activity (fasting timer / daily goal)
- [ ] App Intents / Siri / Shortcuts ("Log a banana", "How many calories left?")
- [ ] Interactive widget button that opens the scanner
- [ ] Apple Watch app (quick log, rings)
- [ ] iCloud sync via SwiftData + CloudKit
- [ ] Local notification meal reminders

## Tier 5: Insights and Analytics
- [ ] Weekly/monthly trend charts (Swift Charts) for calories, macros, weight
- [ ] Streaks and consistency score
- [ ] On-device insight cards ("Protein below goal 5 of 7 days")
- [ ] CSV/PDF export

## Tier 6: UX Polish
- [ ] Haptics (`.sensoryFeedback`) on scan lock-on and save
- [ ] Scan from photo library (`PhotosPicker`)
- [ ] Save meal photo per `MealEntry` (`@Attribute(.externalStorage)`), thumbnails in History
- [ ] Undo after delete; edit past meals
- [ ] Accessibility: VoiceOver on rings/charts, Dynamic Type audit
- [ ] Localization (String Catalogs) and metric/imperial units
- [ ] Empty states, camera-permission-denied screen, torch toggle

## Tier 7: Engineering Quality
- [ ] Protocol-based dependency injection for `ClassifierService` and nutrition source
- [ ] View model tests (Dashboard totals, History filtering, goal math)
- [ ] UI tests for logging flow; snapshot tests
- [ ] Instruments profiling (Core ML + Time Profiler), per-frame latency
- [ ] Model evaluation harness (top-1/top-5 accuracy on a labeled test set)
- [ ] CI: GitHub Actions running `xcodebuild test`
- [ ] `os.Logger` logging and crash reporting
- [ ] Privacy manifest (`PrivacyInfo.xcprivacy`) and App Store readiness
