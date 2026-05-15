//
//  PhotoAttachmentProcessor.swift
//  OffRecord
//
//  Performs image decode and JPEG preparation away from the main actor.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

actor PhotoAttachmentProcessor {
    static let shared = PhotoAttachmentProcessor()

    #if canImport(UIKit)
    func preparedJPEGData(
        from data: Data,
        maxPixelDimension: CGFloat = 2_400,
        compressionQuality: CGFloat = 0.85
    ) -> Data? {
        autoreleasepool {
            guard let image = UIImage(data: data) else { return nil }
            let preparedImage = image.downscaledIfNeeded(maxPixelDimension: maxPixelDimension)
            return preparedImage.jpegData(compressionQuality: compressionQuality)
        }
    }
    #endif
}

#if canImport(UIKit)
private extension UIImage {
    func downscaledIfNeeded(maxPixelDimension: CGFloat) -> UIImage {
        let largestSide = max(size.width, size.height)
        guard largestSide > maxPixelDimension, largestSide > 0 else { return self }

        let scale = maxPixelDimension / largestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
#endif
