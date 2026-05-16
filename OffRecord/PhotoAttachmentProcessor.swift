//
//  PhotoAttachmentProcessor.swift
//  OffRecord
//
//  Performs image decode and JPEG preparation away from the main actor.
//

import Foundation
#if canImport(UIKit)
import ImageIO
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
            let options = [
                kCGImageSourceShouldCache: false
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }

            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
            ] as CFDictionary

            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
            return UIImage(cgImage: thumbnail).jpegData(compressionQuality: compressionQuality)
        }
    }
    #endif
}
