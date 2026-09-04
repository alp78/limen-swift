import Foundation
import Testing
import UIKit
@testable import Limen

/// The app icon, written rather than drawn, from the same seal Android installs.
///
/// Android's adaptive icon is the seal inset 6dp inside a 108dp foreground over the day plate,
/// and a launcher shows the middle 72dp. iOS masks its own corners on a full-bleed square, so the
/// icon is that canvas's middle 72dp on the same plate, which puts the seal at the same size on
/// the home screen as on Android.
@Suite struct AppIconTests {
    private var bundle: Bundle { Bundle(for: LimenModel.self) }

    @Test @MainActor func writeTheAppIcon() throws {
        let out = 1024
        let full = Double(out) * 108 / 72
        let offset = (full - Double(out)) / 2
        let inset = full * 6 / 108
        let seal = try #require(UIImage(named: "limen-seal", in: bundle, compatibleWith: nil))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let icon = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format).image { context in
            UIColor(red: 0xF0 / 255.0, green: 0xED / 255.0, blue: 0xE6 / 255.0, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: out, height: out))
            seal.draw(in: CGRect(x: -offset + inset, y: -offset + inset, width: full - 2 * inset, height: full - 2 * inset))
        }
        let png = try #require(icon.pngData())
        #expect(png.count > 10_000)
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("limen-icon-1024.png")
        try png.write(to: url)
        print("LIMEN_ICON_WRITTEN \(url.path)")
    }
}
