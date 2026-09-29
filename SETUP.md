# NutriVision setup checklist

Things the code can't do for you. Each is a one-time step.

## Signing capabilities (team H2SGDST2MQ)
The entitlements files are in `Config/`. In Xcode, select each target > Signing & Capabilities and let
Xcode register the identifiers (needs a paid developer account for iCloud/HealthKit/App Groups):

| Target | Capability | Value |
|---|---|---|
| NutriVision | HealthKit | (default) |
| NutriVision | App Groups | `group.Janith-Kavinda.NutriVision` |
| NutriVision | iCloud > CloudKit | container `iCloud.Janith-Kavinda.NutriVision` |
| NutriVision | Push Notifications / Background Modes > Remote notifications | needed for live CloudKit updates |
| NutriVisionWidgets | App Groups | `group.Janith-Kavinda.NutriVision` |

Without the App Group, widgets show placeholder data (the app itself still works).
iCloud sync is a toggle in Settings and only takes effect after relaunch.

## Cloud food estimates
Deploy `Proxy/worker.js` (see `Proxy/README.md`), then set the `proxyURL` / `proxyToken`
UserDefaults keys or `AppConfig.defaultProxyURL`. Without it the app uses on-device recognition.
Set a real key in `AppConfig.usdaAPIKey` (DEMO_KEY is rate limited).

## Food detector
Optional: train YOLOv8-nano and add `FoodDetector.mlpackage` (steps in `Proxy/README.md`).

## Apple Watch app
`NutriVisionWatch` has its own scheme and is NOT embedded in the iPhone app, so iPhone builds don't require
the watchOS simulator runtime. Install watchOS in Xcode > Settings > Components, then either run the watch
scheme directly, or embed it for release: add a target dependency on `NutriVisionWatch` and an
"Embed Watch Content" copy phase (destination Products Directory, subpath `$(CONTENTS_FOLDER_PATH)/Watch`)
to the NutriVision target. The watch app needs an app icon in `NutriVisionWatch/Assets.xcassets`.

## Regenerating resources
- `python3 Scripts/generate_food_database.py` rebuilds `FoodDatabase.json`
- `python3 Scripts/generate_localizable.py` rebuilds `Localizable.xcstrings`
- `ruby Scripts/add_extension_targets.rb` was the one-off project edit that added the widget and watch targets

## Evaluating the classifier
Put labelled images in `<dir>/<class name>/*.jpg` and run the tests with `NUTRIVISION_EVAL_DIR=<dir>` set;
`ModelEvaluatorTests.testRealModelOnLabelledDatasetWhenProvided` prints top-1/top-5 accuracy.

## Profiling
Per-frame detection is wrapped in an `os_signpost` interval named `detect` (subsystem `com.nutrivision`,
category `frame`). Profile with Instruments > Time Profiler + Points of Interest + Core ML on a real device.
