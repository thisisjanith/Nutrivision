//
//  ScannerViewModel.swift
//  NutriVision
//

@preconcurrency import AVFoundation
import UIKit
import Observation
import SwiftData

/// One ranked guess from the classifier, with nutrition attached if we can
/// map it.
struct FoodCandidate: Identifiable, Equatable {
    let id = UUID()
    let rawLabel: String
    let confidence: Float
    let nutrition: NutritionProfile?

    var displayName: String { nutrition?.displayName ?? rawLabel.prettifiedClassLabel }
    var confidencePercent: Int { Int((confidence * 100).rounded()) }
    /// The classifier recognised *something*, but it isn't in the nutrition
    /// table — so we can't pre-fill macros and the user has to enter them.
    var hasNutrition: Bool { nutrition != nil }

    static func == (lhs: FoodCandidate, rhs: FoodCandidate) -> Bool { lhs.id == rhs.id }
}

/// The reading currently shown to the user, plus the runners-up they can
/// correct it to.
struct DetectedFood: Identifiable, Equatable {
    let id = UUID()
    let candidate: FoodCandidate
    let alternatives: [FoodCandidate]
    /// User's slider override, applied on top of the model's portion guess.
    var portionScale: Double = 1
    /// Set when the reading came from the cloud model (or its local cache).
    var estimate: CloudFoodEstimate?
    var fromCache = false

    var rawLabel: String { candidate.rawLabel }
    var confidence: Float { candidate.confidence }
    var nutrition: NutritionProfile? { candidate.nutrition }
    var displayName: String { candidate.displayName }
    var confidencePercent: Int { candidate.confidencePercent }
    var hasNutrition: Bool { candidate.hasNutrition }
    var isLowConfidence: Bool { candidate.confidence < lowConfidenceThreshold }

    static let barcodeLabelPrefix = "barcode:"
    static let labelPrefix = "label:"
    static let cloudPrefix = "cloud:"

    /// True for a packaged-product reading from a barcode rather than a
    /// classifier guess. Barcode matches are exact, so the UI skips the
    /// confidence percentage and the "not quite right?" alternatives.
    var isBarcodeScan: Bool { rawLabel.hasPrefix(Self.barcodeLabelPrefix) }

    /// Nutrition read straight off a printed label.
    var isLabelScan: Bool { rawLabel.hasPrefix(Self.labelPrefix) }
    var isCloudEstimate: Bool { rawLabel.hasPrefix(Self.cloudPrefix) }
    /// Exact readings skip the confidence percentage and alternatives.
    var isExact: Bool { isBarcodeScan || isLabelScan }
    /// Anything derived from a model guess rather than a printed source.
    var isEstimated: Bool { !isExact }

    /// Nutrition after the user's portion override.
    var scaledNutrition: NutritionProfile? { nutrition?.scaled(by: portionScale) }

    static func label(_ nutrition: NutritionProfile) -> DetectedFood {
        DetectedFood(
            candidate: FoodCandidate(rawLabel: labelPrefix + nutrition.displayName, confidence: 1.0, nutrition: nutrition),
            alternatives: []
        )
    }

    static func cloud(_ estimate: CloudFoodEstimate, fromCache: Bool) -> DetectedFood {
        var food = DetectedFood(
            candidate: FoodCandidate(
                rawLabel: cloudPrefix + estimate.foodName,
                confidence: Float(estimate.confidenceScore),
                nutrition: estimate.nutritionProfile
            ),
            alternatives: []
        )
        food.estimate = estimate
        food.fromCache = fromCache
        return food
    }

    static func barcode(_ code: String, nutrition: NutritionProfile) -> DetectedFood {
        DetectedFood(
            candidate: FoodCandidate(
                rawLabel: barcodeLabelPrefix + code,
                confidence: 1.0,
                nutrition: nutrition
            ),
            alternatives: []
        )
    }

    /// Promotes one of the runners-up to the primary reading, keeping the
    /// rest (and the displaced primary) available as alternatives.
    func selecting(_ replacement: FoodCandidate) -> DetectedFood {
        var rest = alternatives.filter { $0.id != replacement.id }
        rest.insert(candidate, at: 0)
        var updated = DetectedFood(candidate: replacement, alternatives: rest)
        updated.portionScale = portionScale
        return updated
    }

    static func == (lhs: DetectedFood, rhs: DetectedFood) -> Bool { lhs.id == rhs.id }
}

@MainActor
@Observable
final class ScannerViewModel {
    enum InputMode {
        case liveCamera
        case photoPicker
    }

    let session = AVCaptureSession()
    var inputMode: InputMode = .liveCamera
    var detection: DetectedFood?
    var isClassifying = false
    var cameraAuthorized = false
    var cameraErrorMessage: String?
    var isLookingUpBarcode = false
    /// Transient feedback for a barcode that was read but couldn't be priced.
    var barcodeMessage: String?
    /// Locked viewfinder box (Level 1), nil until the detector stabilises.
    var region: FoodRegion?
    /// Pixel size of the frame `region` refers to, for mapping into the view.
    var frameSize = CGSize(width: 9, height: 16)
    /// Bumped on each lock-on so the view can fire a haptic.
    var lockCount = 0
    var isAnalyzing = false
    var statusMessage: String?
    /// Camera-to-subject distance when the device has LiDAR.
    var distanceMeters: Double? { depthSampler.distanceMeters }
    var hasCapturableFrame: Bool { latestFrame != nil }

    private let videoOutput = AVCaptureVideoDataOutput()
    private let classifier = ClassifierService()
    private let sessionQueue = DispatchQueue(label: "com.nutrivision.scanner.session")
    private var frameSampler: FrameSampler?
    private var stabilizer = DetectionStabilizer()
    private var isSessionConfigured = false
    private let productLookup: any ProductLookup
    private var barcodeScanner: BarcodeScanner?
    private let depthSampler = DepthSampler()
    private let regionDetector: any FoodRegionDetector
    private let visionClient: (any VisionLLMClient)?
    private var cache: EstimateCache?
    private var latestFrame: SendablePixelBuffer?
    private var regionStabilizer = DetectionStabilizer(windowSize: 4, requiredAgreement: 3)
    private var boxSmoother = BoxSmoother()
    private var missedFrames = 0
    private var lastBarcodeAttempt: (code: String, date: Date)?

    /// The scanner sees the same barcode every frame while it's in view; a
    /// repeat inside this window is ignored so we don't hammer the network.
    private let barcodeRetryInterval: TimeInterval = 5

    init(
        productLookup: any ProductLookup = FallbackProductLookup(sources: [OpenFoodFactsClient(), USDAClient()]),
        regionDetector: any FoodRegionDetector = FoodRegionDetectorFactory.makeDefault(),
        visionClient: (any VisionLLMClient)? = ProxyVisionClient.makeDefault()
    ) {
        self.productLookup = productLookup
        self.regionDetector = regionDetector
        self.visionClient = visionClient
    }

    /// Gives the view model the SwiftData context backing the estimate cache.
    func attach(modelContext: ModelContext) {
        if cache == nil { cache = EstimateCache(context: modelContext) }
    }

    /// Floor on the gap between inferences. The sampler also refuses to
    /// dispatch while one is in flight, so on a slower device the real rate
    /// drops below this on its own rather than queueing frames up.
    private let classificationInterval: TimeInterval = 0.2

    func start() async {
        let authorized = await requestCameraAccess()
        cameraAuthorized = authorized
        guard authorized else {
            cameraErrorMessage = "Camera access is required to scan food. Enable it in Settings."
            return
        }
        cameraErrorMessage = nil
        configureSessionIfNeeded()

        let session = self.session
        sessionQueue.async {
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func stop() {
        frameSampler?.reset()
        let session = self.session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func setInputMode(_ mode: InputMode) {
        guard mode != inputMode else { return }
        inputMode = mode
        clearDetection()
        switch mode {
        case .liveCamera:
            Task { await start() }
        case .photoPicker:
            stop()
        }
    }

    func retake() {
        clearDetection()
    }

    /// Swaps the primary reading for one of the ranked alternatives when the
    /// user corrects the model.
    func selectAlternative(_ candidate: FoodCandidate) {
        guard let detection else { return }
        self.detection = detection.selecting(candidate)
        // The user has made a call; stop letting live frames overwrite it.
        stabilizer.reset()
        frameSampler?.reset()
    }

    func classifyPickedImage(_ image: UIImage) async {
        await analyze(image: image, distance: nil)
    }

    /// Shutter: freezes the current frame and identifies it.
    func captureAndAnalyze() async {
        guard let frame = latestFrame, let image = FrameCapture.image(from: frame) else { return }
        await analyze(image: image, distance: distanceMeters)
    }

    /// Reads a printed Nutrition Facts panel from the current frame.
    func scanLabel() async {
        guard let frame = latestFrame, let image = FrameCapture.image(from: frame), !isAnalyzing else { return }
        isAnalyzing = true
        statusMessage = "Reading label…"
        defer { isAnalyzing = false }
        let profile = await Task.detached { try? LabelScanner.scan(image: image) }.value
        if let profile {
            statusMessage = nil
            region = nil
            detection = .label(profile)
        } else {
            statusMessage = "Couldn't read a nutrition label. Hold the panel flat and fill the frame."
        }
    }

    /// Cache → cloud → on-device classifier. Each step is skipped or falls
    /// through on failure so a scan always ends in *some* reading.
    private func analyze(image: UIImage, distance: Double?) async {
        guard !isAnalyzing else { return }
        isAnalyzing = true
        statusMessage = nil
        defer { isAnalyzing = false }

        if let cached = cache?.lookup(image: image) {
            region = nil
            detection = .cloud(cached, fromCache: true)
            return
        }

        if let visionClient, let jpeg = FrameCapture.jpeg(from: image) {
            do {
                let estimate = try await visionClient.estimate(jpeg: jpeg, context: EstimateContext(distanceMeters: distance))
                cache?.store(estimate, image: image)
                region = nil
                detection = .cloud(estimate, fromCache: false)
                return
            } catch {
                statusMessage = "Cloud estimate unavailable — using on-device recognition."
            }
        }

        guard let results = try? await classifier.classify(image: image) else { return }
        // A still image has no temporal noise to smooth, so it's published
        // directly rather than through the stabilizer.
        region = nil
        publish(results)
    }

    private func clearDetection() {
        detection = nil
        barcodeMessage = nil
        statusMessage = nil
        region = nil
        regionStabilizer.reset()
        boxSmoother.reset()
        missedFrames = 0
        stabilizer.reset()
        frameSampler?.reset()
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    private func configureSessionIfNeeded() {
        guard !isSessionConfigured else { return }
        isSessionConfigured = true

        let sampler = FrameSampler(minimumInterval: classificationInterval) { [weak self] frame in
            await self?.handleFrame(frame)
        }
        frameSampler = sampler

        let barcodeScanner = BarcodeScanner { [weak self] code in
            Task { @MainActor in await self?.handleBarcode(code) }
        }
        self.barcodeScanner = barcodeScanner

        let session = self.session
        let videoOutput = self.videoOutput
        let depthOutput: AVCaptureDepthDataOutput? = depthSampler.output

        sessionQueue.async {
            session.beginConfiguration()
            session.sessionPreset = .high

            // Prefer the LiDAR camera so portion estimates get a distance
            // hint; other devices use the plain wide camera.
            let lidar = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back)
            let device = lidar ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }

            videoOutput.setSampleBufferDelegate(sampler, queue: sampler.queue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            // Rotating here means the buffer reaches Vision already upright,
            // so the request handler needs no orientation correction.
            videoOutput.connection(with: .video)?.videoRotationAngle = 90

            if session.canAddOutput(barcodeScanner.output) {
                session.addOutput(barcodeScanner.output)
                barcodeScanner.configureTypes()
            }

            if depthOutput != nil, let device = (session.inputs.first as? AVCaptureDeviceInput)?.device,
               device.deviceType == .builtInLiDARDepthCamera, session.canAddOutput(depthOutput!) {
                session.addOutput(depthOutput!)
            }

            session.commitConfiguration()
        }
    }

    /// Resolves a scanned barcode to nutrition via the product database.
    func handleBarcode(_ code: String) async {
        guard inputMode == .liveCamera, !isLookingUpBarcode else { return }
        // An exact barcode reading is authoritative; don't re-look-up what's
        // already on screen.
        if detection?.rawLabel == DetectedFood.barcodeLabelPrefix + code { return }
        if let last = lastBarcodeAttempt, last.code == code,
           Date().timeIntervalSince(last.date) < barcodeRetryInterval { return }
        lastBarcodeAttempt = (code, Date())

        isLookingUpBarcode = true
        barcodeMessage = nil
        defer { isLookingUpBarcode = false }

        do {
            if let profile = try await productLookup.product(barcode: code) {
                stabilizer.reset()
                detection = .barcode(code, nutrition: profile)
            } else {
                barcodeMessage = "Barcode \(code) isn't in the product database. Try scanning the food itself."
            }
        } catch {
            barcodeMessage = "Couldn't reach the product database. Check your connection."
        }
    }

    private func handleFrame(_ frame: SendablePixelBuffer) async {
        guard inputMode == .liveCamera else { return }
        latestFrame = frame
        // Once something is on screen the result is frozen; the user retakes
        // to look again.
        guard detection == nil, !isAnalyzing else { return }

        frameSize = CGSize(width: CVPixelBufferGetWidth(frame.buffer), height: CVPixelBufferGetHeight(frame.buffer))
        guard let found = await regionDetector.detect(in: frame) else {
            missedFrames += 1
            // Tolerate brief dropouts so the box doesn't flicker.
            if missedFrames >= 4, region != nil {
                region = nil
                regionStabilizer.reset()
                boxSmoother.reset()
            }
            return
        }
        missedFrames = 0

        let stable = regionStabilizer.accept(ClassificationResult(label: found.kind.rawValue, confidence: found.confidence))
        let smoothed = boxSmoother.update(found.box)
        guard let stable else { return }

        let wasLocked = region != nil
        region = FoodRegion(box: smoothed, kind: FoodRegion.Kind(rawValue: stable.label) ?? .food, confidence: stable.confidence)
        if !wasLocked { lockCount += 1 }
    }

    private func publish(_ results: [ClassificationResult]) {
        guard let top = results.first else { return }
        let candidates = results.map { result in
            FoodCandidate(
                rawLabel: result.label,
                confidence: result.confidence,
                nutrition: FoodNutritionMap.lookup(label: result.label)
            )
        }
        // Don't churn the UI when the reading hasn't actually changed.
        if let current = detection, current.rawLabel == top.label { return }
        detection = DetectedFood(candidate: candidates[0], alternatives: Array(candidates.dropFirst()))
    }
}
