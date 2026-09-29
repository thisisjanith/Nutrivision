//
//  BarcodeScanner.swift
//  NutriVision
//

@preconcurrency import AVFoundation

/// Reads product barcodes from the same capture session that feeds the food
/// classifier, using AVFoundation's built-in metadata detection (hardware
/// accelerated, and it costs nothing extra per frame).
///
/// Delivery is on the main queue, which is also the only place the
/// de-duplication state is touched.
nonisolated final class BarcodeScanner: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    /// Retail symbologies only — QR and friends would just add false positives.
    static let supportedTypes: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128]

    let output = AVCaptureMetadataOutput()
    private let onCode: @Sendable (String) -> Void

    init(onCode: @escaping @Sendable (String) -> Void) {
        self.onCode = onCode
        super.init()
        output.setMetadataObjectsDelegate(self, queue: .main)
    }

    /// Must be called after `output` has been added to a session — the
    /// available types are empty until then.
    func configureTypes() {
        output.metadataObjectTypes = Self.supportedTypes.filter(output.availableMetadataObjectTypes.contains)
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let code = metadataObjects
            .compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue })
            .first else { return }
        onCode(code)
    }
}
