import Foundation
import Testing
@testable import LimenKit

/// libjxl as built into this app, checked against itself and against the reference encoder's own
/// output. The stand-in packers of `ArchiveSizeAndPackingTests` prove the archive's handling of a
/// repacked photograph; this proves the library behind `JpegXL.loaded`, on the simulator slice
/// here and on the phone's when the suite runs there.
@Suite struct JpegXLTests {
    private var fixtures: URL {
        get throws { try #require(Bundle(for: JpegXLMarker.self).url(forResource: "Compatibility", withExtension: nil)) }
    }

    @Test func aJpegRepacksSmallerAndUnpacksToTheSameBytes() throws {
        let root = try temporaryRoot()
        let jpeg = try testJPEG(to: root.appendingPathComponent("wall.jpg"), width: 640, height: 480)
        let packer = try #require(JpegXL.loaded)
        let packed = try #require(packer.pack(jpeg))
        #expect(packed.count < jpeg.count)
        #expect(packer.unpack(packed) == jpeg)
        // What is not a JPEG is refused rather than guessed at, in both directions.
        #expect(packer.pack(try testImage(to: root.appendingPathComponent("plan.png"))) == nil)
        #expect(packer.unpack(Data(count: 64)) == nil)
    }

    /// `photo.jxl` was written by cjxl v0.12.0 from `photo.jpg` (`--lossless_jpeg=1 -e 7`), the
    /// same library at the same version the Android build links: what the Pixel repacks, this
    /// build unpacks, and the file this build writes is left for djxl as the other direction.
    @Test func aJpegXlFromTheReferenceEncoderUnpacksToItsJpeg() throws {
        let jpeg = try Data(contentsOf: fixtures.appendingPathComponent("photo.jpg"))
        let packed = try Data(contentsOf: fixtures.appendingPathComponent("photo.jxl"))
        let packer = try #require(JpegXL.loaded)
        #expect(packer.unpack(packed) == jpeg)
        let ours = try #require(packer.pack(jpeg))
        #expect(packer.unpack(ours) == jpeg)
        if let path = ProcessInfo.processInfo.environment["LIMEN_JXL_OUTPUT"] {
            try ours.write(to: URL(fileURLWithPath: path))
            print("LIMEN_JXL_OUTPUT \(path)")
        }
    }

    /// A version 2 backup through the real library: the plain form carries the `jpegxl/` entry
    /// and the marker last, the sealed form restores with the photograph's recorded hash holding,
    /// and the sealed file is left where LIMEN_V2_OUTPUT says for the Pixel to restore.
    @Test func aBackupRepackedByLibjxlRestoresByteForByte() throws {
        let root = try temporaryRoot()
        let sourceRoot = root.appendingPathComponent("source")
        let source = Store(root: sourceRoot)
        let photos = source.photoDir("jxl-entry")
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("photo.jpg"), to: photos.appendingPathComponent("kitchen.jpg"))
        let hash = try ProtocolIntegrity.fileHash(photos.appendingPathComponent("kitchen.jpg"))
        var p = HandoverProtocol(id: "jxl-entry", kind: .entry, createdEpochMs: 1_761_040_000_000)
        p.address = "Rue de l’Échange 2"
        p.place = "1003 Lausanne"
        p.rooms = [Room(id: "r1", kind: .kitchen, inspected: true)]
        p.defects = [Defect(id: "d1", roomId: "r1", text: "Photographie repaquetée", photos: ["kitchen.jpg"],
                            photoEvidence: [PhotoEvidence("kitchen.jpg", sha256: hash, capturedEpochMs: 1_761_040_100_000, source: .camera)])]
        try source.save(p)

        let plain = root.appendingPathComponent("plain.zip")
        try ArchiveIO.export(root: sourceRoot, to: plain)
        let reader = try Zip.Reader(plain)
        let names = reader.entries.map(\.name)
        #expect(names.contains("jpegxl/jxl-entry/kitchen.jpg") && !names.contains("photos/jxl-entry/kitchen.jpg"))
        #expect(names.last == "limen-archive.txt")
        let marker = try #require(reader.entries.last)
        #expect(try reader.read(marker) == Data("LIMEN_ARCHIVE\nversion=2\n".utf8))

        let sealed = root.appendingPathComponent("sealed.limen")
        try source.exportArchive(password: "limen 1.2.5", to: sealed)
        let restored = Store(root: root.appendingPathComponent("restored"))
        #expect(try restored.importArchive(password: "limen 1.2.5", from: sealed).imported == 1)
        #expect(try ProtocolIntegrity.fileHash(restored.photoDir("jxl-entry").appendingPathComponent("kitchen.jpg")) == hash)
        if let path = ProcessInfo.processInfo.environment["LIMEN_V2_OUTPUT"] {
            try? FileManager.default.removeItem(atPath: path)
            try FileManager.default.copyItem(at: sealed, to: URL(fileURLWithPath: path))
            print("LIMEN_V2_OUTPUT \(path)")
        }
    }
}

private final class JpegXLMarker: NSObject {}
