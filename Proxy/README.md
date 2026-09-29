# NutriVision proxy and detector notes

## Vision-LLM proxy
`worker.js` is a Cloudflare Worker that forwards a captured frame to Claude Haiku and returns the
JSON the app decodes as `CloudFoodEstimate`. Deploy it, then in the app set
`UserDefaults` keys `proxyURL` (and `proxyToken`) or change `AppConfig.defaultProxyURL`.
With no proxy configured the app falls back to the on-device classifier.

## Food detector (YOLOv8-nano)
The live viewfinder uses `FoodRegionDetectorFactory`. Without a bundled model it uses Vision saliency.
To use a trained detector, train YOLOv8n on a Food-101/UEC-Food style dataset with every label
collapsed to `food` (drinks to `beverage`), then export:

    pip install ultralytics coremltools
    yolo export model=best.pt format=coreml nms=True imgsz=640

Add the resulting `FoodDetector.mlpackage` to the NutriVision target; Xcode compiles it to
`FoodDetector.mlmodelc`, which the factory picks up automatically.
