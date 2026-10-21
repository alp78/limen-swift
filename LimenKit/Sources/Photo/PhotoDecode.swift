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
        // In a pool of its own: ImageIO's buffers are autoreleased, and every photograph of a
        // record is checked in one synchronous call before an export and after a restore.
        autoreleasepool {
            guard let (width, height) = bounds(file), let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  CGImageSourceGetStatus(source) == .statusComplete,
                  let image = sampled(source, width: width, height: height, targetWidth: 256),
                  let context = CGContext(data: nil, width: image.width, height: image.height,
                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete
        }
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
        let uprightWidth = quarterTurned(source) ? height : width
        let scale = Double(targetWidth) / Double(uprightWidth)
        let pixels = max(Int(Double(longest) * min(scale, 1)), 1)
        return thumbnail(source, maxPixels: pixels)
    }

    /// The photograph's pixel size once turned upright, read from its header without decoding
    /// it. The annex fits a picture as it will stand on paper, and its counting pass must know
    /// that size without decoding anything.
    public static func uprightSize(_ file: URL) -> (width: Int, height: Int)? {
        guard let (width, height) = bounds(file), let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return quarterTurned(source) ? (height, width) : (width, height)
    }

    /// The photograph upright at exactly `width` × `height` pixels, both upright dimensions,
    /// which is what the PDF annex prints. ImageIO's thumbnail path takes the long edge and
    /// applies the EXIF transform; when it comes back a pixel off the target, one filtered redraw
    /// makes the size exact, as Android does after its power-of-two sampling. The thumbnail is
    /// the standard-range picture: an HDR capture's gain map is not part of it, which is what
    /// paper prints.
    public static func uprightAtSize(_ file: URL, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, bounds(file) != nil, let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let decoded = thumbnail(source, maxPixels: max(width, height)) else { return nil }
        if decoded.width == width, decoded.height == height { return decoded }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func thumbnail(_ source: CGImageSource, maxPixels: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A quarter turn swaps the edges: EXIF orientations 5 to 8 are the transposed ones.
    private static func quarterTurned(_ source: CGImageSource) -> Bool {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation)
    }

    /// The pixel size, without decoding the picture. No bound on it: a photograph is kept as it
    /// was taken, however large, and a decode that fails on a real one is fixed in the decode.
    public static func bounds(_ file: URL) -> (Int, Int)? {
        var isDirectory: ObjCBool = false
        guard Files.isRegularFile(file), FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }
}
