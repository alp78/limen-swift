import CoreGraphics
import Foundation

/// The size a photograph prints at in the annex, and the pixels it is decoded to for that.
///
/// The Android app computes the same numbers from the same rule and asserts the same table, so a
/// record exported on either phone carries the same plates at the same resolution. Pure
/// arithmetic on purpose: the decoding needs ImageIO, the decision does not.
public enum AnnexPlate {
    /// The width inside an annex card's frame, 1240 units less both margins and the frame's
    /// padding, and the height that still leaves the card's legend and a section title on the
    /// page. A landscape photograph prints about 17 cm wide, a portrait one 19 cm high.
    public static let maxWidth: Double = 1020
    public static let maxHeight: Double = 1100

    /// 200 dpi. One unit is 0.169 mm on the 1240-unit A4 page, so one pixel per unit is 150 dpi.
    /// Thirty photographs made a 137 MB PDF at 300 dpi lossless on Android, and make 7.7 MB at
    /// 200 dpi as JPEG at `jpegQuality`.
    private static let pixelsPerUnit = 200.0 / 150.0

    /// The plates' JPEG quality, the same in the PDF and in its HTML copy.
    /// Android's `Bitmap.compress(JPEG, 85)` is libjpeg's quality scale; ImageIO's is a different
    /// curve, and 0.85 on it quantises almost twice as finely: thirty 12-megapixel photographs
    /// made a 14.0 MB PDF where Android makes 7.7 MB. Measured on the same plates, ImageIO at 0.60
    /// writes what libjpeg writes at 85, 0.97 times the bytes with a slightly finer luminance
    /// table (mean quantiser 15.8 against 17.3), so this is Android's plate, not Android's number.
    public static let jpegQuality = 0.60

    /// `boxWidth` × `boxHeight` in page units; `pixelWidth` × `pixelHeight` decoded, both upright.
    public struct Fit: Equatable, Sendable {
        public let boxWidth: CGFloat
        public let boxHeight: CGFloat
        public let pixelWidth: Int
        public let pixelHeight: Int
    }

    /// `width` × `height` are the photograph's upright pixel dimensions, read before decoding.
    public static func fit(_ width: Int, _ height: Int) -> Fit {
        let scale = min(maxWidth / Double(width), maxHeight / Double(height))
        let boxWidth = Double(width) * scale
        let boxHeight = Double(height) * scale
        // A picture smaller than its box is drawn as it is: enlarging adds pixels and no detail.
        let long = min(max(width, height), Int((pixelsPerUnit * max(boxWidth, boxHeight)).rounded()))
        let pixelWidth: Int
        let pixelHeight: Int
        if width >= height {
            pixelWidth = long
            pixelHeight = Int((Double(long) * Double(height) / Double(width)).rounded())
        } else {
            pixelWidth = Int((Double(long) * Double(width) / Double(height)).rounded())
            pixelHeight = long
        }
        return Fit(boxWidth: CGFloat(boxWidth), boxHeight: CGFloat(boxHeight), pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }
}
