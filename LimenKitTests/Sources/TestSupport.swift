import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
import Testing
@testable import LimenKit

/// A scratch folder per test, removed when the test ends.
func temporaryRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("limen-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func writeText(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

func readText(_ url: URL) -> String {
    String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self)
}

func makeDir(_ url: URL) throws -> URL {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Real pixel data keeps decoding tests separate from the byte-only fingerprint contract.
func testImage(to url: URL, width: Int = 24, height: Int = 12, orientation: Int = 1, noise: Bool = false) throws -> Data {
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    var seed: UInt64 = 0xA417
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            if noise {
                for channel in 0..<3 {
                    seed = seed &* 6_364_136_223_846_793_005 &+ 1
                    pixels[offset + channel] = UInt8(truncatingIfNeeded: seed >> 32)
                }
            } else {
                let quadrant = (y >= height / 2 ? 2 : 0) + (x >= width / 2 ? 1 : 0)
                let colors: [[UInt8]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]]
                for channel in 0..<3 { pixels[offset + channel] = colors[quadrant][channel] }
            }
        }
    }
    let data = Data(pixels)
    let provider = try #require(CGDataProvider(data: data as CFData))
    let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let type = orientation == 1 ? UTType.png.identifier : UTType.tiff.identifier
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return try Data(contentsOf: url)
}

func testPDF(to url: URL) throws -> Data {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var bounds = CGRect(x: 0, y: 0, width: 595.276, height: 841.89)
    let context = try #require(CGContext(url as CFURL, mediaBox: &bounds, nil))
    context.beginPDFPage(nil)
    context.setFillColor(CGColor(gray: 0.4, alpha: 1))
    context.fill(CGRect(x: 40, y: 40, width: 120, height: 90))
    context.endPDFPage(); context.closePDF()
    return try Data(contentsOf: url)
}
