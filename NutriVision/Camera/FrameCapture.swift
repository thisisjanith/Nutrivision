//
//  FrameCapture.swift
//  NutriVision
//

import CoreImage
import UIKit

nonisolated enum FrameCapture {
    private static let context = CIContext()

    /// Converts a camera frame to an upright `UIImage`. The capture connection
    /// already rotates buffers, so no orientation fix-up is needed.
    static func image(from frame: SendablePixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: frame.buffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Downscaled JPEG for upload — vision models don't benefit from full
    /// sensor resolution and it keeps the request small and cheap.
    static func jpeg(from image: UIImage, maxDimension: CGFloat = 1024, quality: CGFloat = 0.7) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
