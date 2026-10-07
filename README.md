# NutriVision

An iOS app that logs meals by pointing the camera at food. It recognizes the dish, estimates calories and macros, and saves the result to a daily log.

Built with Swift, SwiftUI and SwiftData.

## Screenshots

| Home | Scanner | Result |
| --- | --- | --- |
| _add screenshot_ | _add screenshot_ | _add screenshot_ |

## Features

- **Food scanning:** live camera with a lock-on box, then capture and identify.
- **Barcode scanning:** looks up packaged food and reads nutrition per serving.
- **Label scanning:** reads a Nutrition Facts panel with on-device text recognition.
- **Portion control:** preset buttons and a slider, plus one tap alternative guesses.
- **Manual logging:** food search, custom foods and favorites.
- **Dashboard:** calorie and macro rings, water tracking, fasting timer.
- **Insights:** streaks, consistency score, weekly totals, weight trend and goal date estimate.
- **Extras:** meal reminders, CSV and PDF export, Apple Health sync, optional iCloud sync.
- **Ecosystem:** Home Screen and Lock Screen widgets, fasting Live Activity, Siri shortcuts, Apple Watch app.
- **Design:** dark theme with the native iOS 26 Liquid Glass tab bar.

## How recognition works

The app tries the best source first and falls back safely.

1. Barcode match, if a code is found.
2. Cloud vision model estimate, cached for repeat scans.
3. On-device Core ML classifier (EfficientNetV2-S fine tuned on Food-101) when offline or if the cloud fails.
4. Nutrition lookup from a local food database.
5. User correction with alternatives, portion and macro sliders.

A detection stabilizer only publishes a label after it wins a majority of recent frames, which stops flicker.

## Requirements

- Xcode 26 or later
- iOS 17 or later (Liquid Glass needs iOS 26)
- A real iPhone for the camera. LiDAR is optional and improves portion hints.

## Getting started

1. Clone the repo and open `NutriVision.xcodeproj`.
2. Select the `NutriVision` scheme and an iPhone.
3. Set your own team in Signing and Capabilities.
4. Run the app.

Widgets, HealthKit and iCloud need extra capabilities and a paid developer account. See [SETUP.md](SETUP.md) for the full checklist. Without the App Group, widgets show placeholder data and the app still works.

### Optional: cloud estimates

Deploy the Cloudflare Worker in [Proxy](Proxy/README.md), then set the `proxyURL` and `proxyToken` values. Without it, the app uses on-device recognition only.

## Project structure

| Folder | Purpose |
| --- | --- |
| `NutriVision/Views` | SwiftUI screens grouped by feature |
| `NutriVision/ViewModels` | Scanner and dashboard state and logic |
| `NutriVision/Models` | SwiftData entities |
| `NutriVision/ML` | Classifier, region detector, stabilizer, nutrition lookup |
| `NutriVision/Camera` | Frame sampling, barcode, label and depth capture |
| `NutriVision/Services` | Networking, health, tracking, fasting, export, reminders |
| `NutriVision/Utilities` | Theme and reusable modifiers |
| `NutriVisionWidgets` | Widgets and Live Activity |
| `NutriVisionWatch` | Apple Watch companion |
| `Proxy` | Cloud estimate worker |
| `Scripts` | Model conversion, icon and data generators |

The app follows MVVM. Widgets and the watch read a small JSON snapshot through an App Group, never the database directly.

## Testing

Run tests in Xcode with `Cmd+U`. The suite has about 107 unit test functions plus UI tests for the logging flow. Network and ML are replaced with fakes so tests are repeatable.

To measure classifier accuracy, put labelled images in `<dir>/<class name>/*.jpg` and run the tests with `NUTRIVISION_EVAL_DIR=<dir>` set.

## Profiling

Per frame detection is wrapped in an `os_signpost` interval named `detect`. Profile it in Instruments with Time Profiler, Points of Interest and Core ML on a real device.

## Tech used

Core ML, Vision, AVFoundation (LiDAR depth), SwiftData, HealthKit, WidgetKit, ActivityKit, App Intents, WatchConnectivity, CloudKit.

## Repository

https://github.com/thisisjanith/Nutrivision
