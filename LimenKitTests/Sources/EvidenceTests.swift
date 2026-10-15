import CoreGraphics
import Foundation
import Testing
@testable import LimenKit

@Suite struct EvidenceTests {
    @Test func everyExifOrientationDecodesWithTheExpectedUprightDimensions() throws {
        let root = try temporaryRoot()
        var baseline: [[UInt8]] = []
        let permutations = [[0, 1, 2, 3], [1, 0, 3, 2], [3, 2, 1, 0], [2, 3, 0, 1],
                            [0, 2, 1, 3], [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2]]
        for orientation in 1...8 {
            let url = root.appendingPathComponent("orientation-\(orientation).image")
            _ = try testImage(to: url, orientation: orientation)
            #expect(PhotoDecode.readable(url))
            let image = try #require(PhotoDecode.sampled(url, targetWidth: 24))
            #expect(image.width == (orientation >= 5 ? 12 : 24))
            #expect(image.height == (orientation >= 5 ? 24 : 12))
            let pixels = try corners(image)
            if orientation == 1 { baseline = pixels }
            #expect(pixels == permutations[orientation - 1].map { baseline[$0] }, "mirror/rotation at orientation \(orientation)")
        }
    }

    @Test func rotatedPortraitSamplingUsesTheDisplayedWidth() throws {
        let root = try temporaryRoot(), file = root.appendingPathComponent("rotated.tiff")
        _ = try testImage(to: file, width: 12, height: 24, orientation: 6)
        let image = try #require(PhotoDecode.sampled(file, targetWidth: 12))
        #expect(image.width == 12)
        #expect(image.height == 6)
    }

    private func corners(_ image: CGImage) throws -> [[UInt8]] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return [(width / 4, height / 4), (width * 3 / 4, height / 4), (width / 4, height * 3 / 4), (width * 3 / 4, height * 3 / 4)].map { x, y in
            let index = (y * width + x) * 4
            return Array(bytes[index..<(index + 3)])
        }
    }

    @Test func missingEmptyHeaderOnlyTruncatedAndHashMismatchHaveNamedFailures() throws {
        let root = try temporaryRoot(), photos = try makeDir(root.appendingPathComponent("photos")), ink = try makeDir(root.appendingPathComponent("ink"))
        let valid = try testImage(to: photos.appendingPathComponent("good.png"))
        try Data().write(to: photos.appendingPathComponent("empty.png"))
        try valid.prefix(32).write(to: photos.appendingPathComponent("header.png"))
        try valid.prefix(valid.count / 2).write(to: photos.appendingPathComponent("truncated.png"))
        for name in ["missing.png", "empty.png", "header.png", "truncated.png"] {
            #expect(!PhotoDecode.readable(photos.appendingPathComponent(name)))
        }
        var p = HandoverProtocol(id: "e", kind: .entry, createdEpochMs: 1)
        p.details.roomPhotos["r"] = [PhotoEvidence("good.png", sha256: String(repeating: "0", count: 64))]
        p.signatures = [Signature(.tenant, plane: .record, file: "missing-ink.png")]
        #expect(Set(EvidenceValidation.unreadable(p, photoDir: photos, signatureDir: ink)) == ["good.png", "missing-ink.png"])
        #expect(throws: EvidenceValidation.UnrenderableEvidence.self) { try EvidenceValidation.requireReadable(p, photoDir: photos, signatureDir: ink) }
    }

    @Test func mediaTypeComesFromBytesAndDocumentsHaveContentAndSizeValidation() throws {
        let root = try temporaryRoot()
        let disguised = root.appendingPathComponent("picture.jpg")
        _ = try testImage(to: disguised)
        #expect(try EvidenceValidation.validatePhoto(disguised) == "image/png")
        let pdf = root.appendingPathComponent("lease.bin")
        _ = try testPDF(to: pdf)
        #expect(try EvidenceValidation.validateDocument(pdf) == "application/pdf")
        let fake = root.appendingPathComponent("fake.pdf")
        try writeText("%PDF-1.4 incomplete", to: fake)
        #expect(throws: EvidenceValidation.UnrenderableEvidence.self) { try EvidenceValidation.validateDocument(fake) }
        let huge = root.appendingPathComponent("too-large.png")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(EvidenceValidation.maxIntakeBytes + 1)); try handle.close()
        #expect(throws: EvidenceValidation.UnrenderableEvidence.self) { try EvidenceValidation.validatePhoto(huge) }
    }

    @Test func symlinkedEvidenceCannotBeHashedOrImported() throws {
        let root = try temporaryRoot(), photo = root.appendingPathComponent("image.png"), alias = root.appendingPathComponent("alias.png")
        _ = try testImage(to: photo)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: photo)
        #expect(throws: ProtocolIntegrity.IntegrityError.self) { try ProtocolIntegrity.fileHash(alias) }
        #expect(throws: EvidenceValidation.UnrenderableEvidence.self) { try EvidenceValidation.validatePhoto(alias) }
    }
}
