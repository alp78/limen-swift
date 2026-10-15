import CoreGraphics
import Foundation
import ImageIO

/// One rotation-aware read of a photograph on disk.
///
/// The editor's thumbnails and the exported annex used to hold a decoder each, and only the
/// export applied EXIF rotation: a capture taken sideways showed sideways in the app and printed
/// upright on the paper, which reads as the export having altered the evidence.
public enum PhotoDecode {
    /// True when the file decodes at all, which is what the annex's two passes must agree on.
    public static func readable(_ file: URL) -> Bool {
        guard let (width, height) = bounds(file), let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              let image = sampled(source, width: width, height: height, targetWidth: 256),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
    }

    /// The photograph at roughly `targetWidth`, turned upright. Sampling happens during the
    /// decode rather than after it, so a twelve-megapixel capture never occupies full size in
    /// memory: three of those at once is the allocation an inspector's phone actually refuses.
    public static func sampled(_ file: URL, targetWidth: Int) -> CGImage? {
        guard targetWidth > 0, let (width, height) = bounds(file), let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return sampled(source, width: width, height: height, targetWidth: targetWidth)
    }

    private static func sampled(_ source: CGImageSource, width: Int, height: Int, targetWidth: Int) -> CGImage? {
        // ImageIO's thumbnail path applies the EXIF orientation itself and decodes at the
        // requested size; the size is the longer edge, so the width asked for is honoured
        // whichever way the picture was taken.
        // Against the width, not the shorter edge: dividing by the short edge honoured the
        // request only on a portrait picture and decoded a landscape one oversized by its aspect
        // ratio, which is the opposite of what this function exists to avoid.
        let longest = max(width, height)
        // Transposed orientations swap the displayed axes. Using the stored width made a
        // rotated portrait decode wider than the requested display budget.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let uprightWidth = (5...8).contains(orientation) ? height : width
        let scale = Double(targetWidth) / Double(uprightWidth)
        let pixels = max(Int(Double(longest) * min(scale, 1)), 1)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The pixel size, without decoding the picture.
    public static func bounds(_ file: URL) -> (Int, Int)? {
        var isDirectory: ObjCBool = false
        guard Files.isRegularFile(file), FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0, width <= 32_768, height <= 32_768,
              Int64(width) * Int64(height) <= 80_000_000 else { return nil }
        return (width, height)
    }
}
