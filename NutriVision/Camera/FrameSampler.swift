//
//  FrameSampler.swift
//  NutriVision
//

@preconcurrency import AVFoundation

/// Bridges AVFoundation's capture callback to an async classifier.
///
/// Two jobs, both about not drowning the model:
///
/// 1. **Interval throttling** — the camera delivers ~30 fps; we only need a
///    few inferences a second for a stable read.
/// 2. **Backpressure** — a frame is only dispatched when the previous one has
///    finished. Without this, a slow inference on a cold Neural Engine queues
///    frames faster than they drain and the UI falls behind the camera.
///
/// All mutable state lives on `queue`, which AVFoundation calls serially and
/// which every completion bounces back through, so no lock is needed.
nonisolated final class FrameSampler: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// The queue AVFoundation must deliver sample buffers on. Pass this to
    /// `setSampleBufferDelegate(_:queue:)` — the state confinement below
    /// depends on it.
    let queue: DispatchQueue

    private let minimumInterval: TimeInterval
    private let handler: @Sendable (SendablePixelBuffer) async -> Void

    private var lastDispatch = Date.distantPast
    private var isInFlight = false

    init(
        minimumInterval: TimeInterval,
        handler: @escaping @Sendable (SendablePixelBuffer) async -> Void
    ) {
        self.queue = DispatchQueue(label: "com.nutrivision.scanner.frames", qos: .userInitiated)
        self.minimumInterval = minimumInterval
        self.handler = handler
        super.init()
    }

    /// Stops any further frames from being dispatched until the next one that
    /// clears the interval — used when the scanner pauses or changes mode, so
    /// a stale in-flight frame can't publish a detection afterwards.
    func reset() {
        queue.async {
            self.lastDispatch = .distantPast
            self.isInFlight = false
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        dispatchPrecondition(condition: .onQueue(queue))

        guard !isInFlight else { return }

        let now = Date()
        guard now.timeIntervalSince(lastDispatch) >= minimumInterval else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lastDispatch = now
        isInFlight = true

        // Holding this Swift reference retains the buffer, so the capture pool
        // can't recycle it out from under the classifier mid-inference.
        let frame = SendablePixelBuffer(buffer: pixelBuffer)
        let handler = self.handler
        let queue = self.queue

        Task { [weak self] in
            await handler(frame)
            queue.async { self?.isInFlight = false }
        }
    }
}
