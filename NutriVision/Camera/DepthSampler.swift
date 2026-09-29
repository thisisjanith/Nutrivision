//
//  DepthSampler.swift
//  NutriVision
//

@preconcurrency import AVFoundation

/// Reads camera-to-subject distance from the LiDAR depth camera so the vision
/// model can judge portion size. Uses AVFoundation's depth output rather than
/// ARKit because ARKit takes exclusive control of the camera, which would
/// stop the live preview and barcode scanning.
///
/// Devices without LiDAR never receive depth data; `distanceMeters` stays nil
/// and the estimate simply goes without a distance hint.
nonisolated final class DepthSampler: NSObject, AVCaptureDepthDataOutputDelegate, @unchecked Sendable {
    let output = AVCaptureDepthDataOutput()
    private let queue = DispatchQueue(label: "com.nutrivision.scanner.depth", qos: .utility)
    private let lock = NSLock()
    private var latest: Double?

    override init() {
        super.init()
        output.isFilteringEnabled = true
        output.setDelegate(self, callbackQueue: queue)
    }

    var distanceMeters: Double? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData,
                         timestamp: CMTime, connection: AVCaptureConnection) {
        let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let value = Self.centerDistance(of: converted.depthDataMap)
        lock.lock(); latest = value; lock.unlock()
    }

    /// Median of valid readings in the central 20% window; the median shrugs
    /// off dropouts and the plate rim at the edges.
    static func centerDistance(of map: CVPixelBuffer) -> Double? {
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        let x0 = Int(Double(width) * 0.4), x1 = Int(Double(width) * 0.6)
        let y0 = Int(Double(height) * 0.4), y1 = Int(Double(height) * 0.6)

        var values: [Float] = []
        for y in y0..<max(y0 + 1, y1) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in x0..<max(x0 + 1, x1) where row[x].isFinite && row[x] > 0.1 && row[x] < 5 {
                values.append(row[x])
            }
        }
        guard !values.isEmpty else { return nil }
        values.sort()
        return Double(values[values.count / 2])
    }
}
