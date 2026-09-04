import Foundation
import Testing
import UIKit
@testable import Limen

/// The app icon, written rather than drawn, from the same seal Android installs.
///
/// Android's adaptive icon is the seal inset 6dp inside a 108dp foreground over the day plate, and
/// the launcher masks it to a circle or a squircle, so the art is drawn to survive inside the 66dp
/// safe circle. iOS masks only the corners of a full square, so carrying that composition over
/// cropped the seal: taking the canvas's middle 72dp cut the top and the bottom off a round seal
/// that was drawn to reach the mask's edge.
///
/// The seal is therefore measured by what it actually paints, then centred on the day plate and
/// grown until it spans the tile. Nothing is cropped and the artwork itself is untouched: only its
/// size and its place on the tile change.
///
/// The PNG is written without an alpha channel. `opaque` alone leaves an all-255 channel in the
/// file, and App Store Connect refuses an icon that carries one at all.
@Suite struct AppIconTests {
    /// The share of the tile's width the seal spans.
    ///
    /// The seal is round and carries its wording around the rim, so the most of the tile it can
    /// take is a circle inscribed in it: any larger and the squircle mask starts eating LIMEN
    /// PACTORUM ET IURIUM. The two percent left over is the antialiased edge, not a margin.
    private let markFraction = 0.98

    private var bundle: Bundle { Bundle(for: LimenModel.self) }

    /// The day plate the Android background names, which fills the tile to its edges.
    private var plate: UIColor {
        UIColor(red: 0xF0 / 255.0, green: 0xED / 255.0, blue: 0xE6 / 255.0, alpha: 1)
    }

    @MainActor private func render(_ name: String, size: Int) throws -> UIImage {
        let image = try #require(UIImage(named: name, in: bundle, compatibleWith: nil))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    /// One image read back as pixels, so the measurements below walk them rather than guess.
    private struct Raster {
        let pixels: [UInt32]
        let width: Int
        let height: Int
    }

    /// One ARGB read of an image, so the measurements below walk pixels rather than guess.
    private func rgba(_ image: UIImage) throws -> Raster {
        let cg = try #require(image.cgImage)
        let width = cg.width
        let height = cg.height
        var pixels = [UInt32](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        #expect(drawn)
        return Raster(pixels: pixels, width: width, height: height)
    }

    /// What the art actually paints, in the pixels of the image handed in.
    ///
    /// The seal is placed by this rather than by the canvas it was drawn on: the Android foreground
    /// carries its own 6dp margin to the 108dp edge, and centring the canvas would centre that
    /// margin instead of the drawing.
    private func paintedBox(_ image: UIImage) throws -> CGRect {
        let raster = try rgba(image)
        let pixels = raster.pixels
        let width = raster.width
        let height = raster.height
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where (pixels[y * width + x] >> 24) & 0xFF >= 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        #expect(maxX >= minX && maxY >= minY, "the seal paints nothing")
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// The seal's own extent inside a filled tile, found by what differs from the plate colour.
    private func inkBox(_ image: UIImage) throws -> CGRect {
        let raster = try rgba(image)
        let pixels = raster.pixels
        let width = raster.width
        let height = raster.height
        let background = pixels[0] & 0x00FF_FFFF
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where (pixels[y * width + x] & 0x00FF_FFFF) != background {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        #expect(maxX >= minX && maxY >= minY, "the tile carries no seal")
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// PNG bytes with no alpha channel at all, which is what an App Store icon has to be.
    private func opaquePNG(_ cg: CGImage) throws -> Data {
        let width = cg.width
        let height = cg.height
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let flattened = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, flattened, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @MainActor private func drawIcon(size out: Int) throws -> UIImage {
        let probe = 512
        let box = try paintedBox(try render("limen-seal", size: probe))
        // Scale by the painted box, not the canvas, and place that box's centre on the tile's.
        let span = Double(max(box.width, box.height))
        let scale = markFraction * Double(out) / span
        let drawn = Double(probe) * scale
        let originX = Double(out) / 2 - box.midX * scale
        let originY = Double(out) / 2 - box.midY * scale
        let seal = try #require(UIImage(named: "limen-seal", in: bundle, compatibleWith: nil))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format).image { context in
            plate.setFill()
            context.fill(CGRect(x: 0, y: 0, width: out, height: out))
            seal.draw(in: CGRect(x: originX, y: originY, width: drawn, height: drawn))
        }
    }

    @Test @MainActor func writeTheAppIcon() throws {
        let out = 1024
        let png = try opaquePNG(try #require(try drawIcon(size: out).cgImage))
        #expect(png.count > 10_000)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("limen-icon-1024.png")
        try png.write(to: url)
        print("LIMEN_ICON_WRITTEN \(url.path)")
    }

    /// The tile is opaque to its corners and the seal is whole inside it.
    ///
    /// The second half is what the Android composition broke: a round seal drawn to its mask's
    /// edge came out with its top and bottom cut off by the square.
    @Test @MainActor func theSealIsWholeOnAFullTile() throws {
        let out = 256
        let icon = try drawIcon(size: out)
        let raster = try rgba(icon)
        let pixels = raster.pixels
        let width = raster.width
        for corner in [0, width - 1, width * (width - 1), width * width - 1] {
            #expect((pixels[corner] >> 24) & 0xFF == 0xFF, "a corner of the tile is not opaque")
        }
        let ink = try inkBox(icon)
        #expect(ink.minX > 0 && ink.minY > 0 && ink.maxX < Double(out) && ink.maxY < Double(out))
        let span = Double(max(ink.width, ink.height)) / Double(out)
        #expect(abs(span - markFraction) < 0.02, "the seal spans \(span) of the tile")
    }
}
