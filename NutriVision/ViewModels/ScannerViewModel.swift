//
//  ScannerViewModel.swift
//  NutriVision
//

@preconcurrency import AVFoundation
import UIKit
import Observation

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

    var rawLabel: String { candidate.rawLabel }
    var confidence: Float { candidate.confidence }
    var nutrition: NutritionProfile? { candidate.nutrition }
    var displayName: String { candidate.displayName }
    var confidencePercent: Int { candidate.confidencePercent }
    var hasNutrition: Bool { candidate.hasNutrition }
    var isLowConfidence: Bool { candidate.confidence < lowConfidenceThreshold }

    /// Promotes one of the runners-up to the primary reading, keeping the
    /// rest (and the displaced primary) available as alternatives.
    func selecting(_ replacement: FoodCandidate) -> DetectedFood {
        var rest = alternatives.filter { $0.id != replacement.id }
        rest.insert(candidate, at: 0)
        return DetectedFood(candidate: replacement, alternatives: rest)
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

    private let videoOutput = AVCaptureVideoDataOutput()
    private let classifier = ClassifierService()
    private let sessionQueue = DispatchQueue(label: "com.nutrivision.scanner.session")
    private var frameSampler: FrameSampler?
    private var stabilizer = DetectionStabilizer()
    private var isSessionConfigured = false

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
        isClassifying = true
        defer { isClassifying = false }
        guard let results = try? await classifier.classify(image: image) else { return }
        // A still image has no temporal noise to smooth, so it's published
        // directly rather than through the stabilizer.
        publish(results)
    }

    private func clearDetection() {
        detection = nil
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

        let session = self.session
        let videoOutput = self.videoOutput

        sessionQueue.async {
            session.beginConfiguration()
            session.sessionPreset = .high

            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
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

            session.commitConfiguration()
        }
    }

    private func handleFrame(_ frame: SendablePixelBuffer) async {
        guard inputMode == .liveCamera else { return }

        isClassifying = true
        defer { isClassifying = false }

        guard let results = try? await classifier.classify(pixelBuffer: frame, orientation: .up),
              let top = results.first else { return }

        // Only publish once a label has held steady across several frames.
        guard let stable = stabilizer.accept(top) else { return }
        publish([stable] + results.dropFirst())
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
