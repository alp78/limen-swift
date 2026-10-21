import Foundation
import Testing
@testable import LimenKit

/// Deflate standing in for libjxl, which the unit suite does not have to run: it shrinks the
/// zero-filled test JPEGs and gives them back exactly. The same stand-in Android's JVM suite uses.
private struct Deflating: JpegPacker {
    func pack(_ jpeg: Data) -> Data? { Deflate.compress(jpeg) }
    func unpack(_ packed: Data) -> Data? { Deflate.decompress(packed, expected: 1 << 24) }
}

/// A packer that would not give the bytes back: the backup must then keep the original.
private struct Unfaithful: JpegPacker {
    func pack(_ jpeg: Data) -> Data? { Deflating().pack(jpeg) }
    func unpack(_ packed: Data) -> Data? {
        guard var bytes = Deflating().unpack(packed), !bytes.isEmpty else { return nil }
        bytes[bytes.count - 1] = 0
        return bytes
    }
}

@Suite struct ArchiveSizeAndPackingTests {
    private func entries(_ archive: URL) throws -> [String: Data] {
        let reader = try Zip.Reader(archive)
        var out: [String: Data] = [:]
        for entry in reader.entries { out[entry.name] = try reader.read(entry) }
        return out
    }

    /// A record with one JPEG and one PNG photograph, the JPEG's hash recorded as at capture. Real
    /// images, because the export checks that every photograph decodes before it goes in.
    private struct Photographed {
        let root: URL
        let jpeg: Data
        let png: Data
    }

    private func withPhotographs(_ root: URL) throws -> Photographed {
        let store = Store(root: root)
        let jpeg = try testJPEG(to: store.photoDir("photos").appendingPathComponent("wall.jpg"))
        let png = try testImage(to: store.photoDir("photos").appendingPathComponent("plan.png"))
        let hash = try ProtocolIntegrity.fileHash(store.photoDir("photos").appendingPathComponent("wall.jpg"))
        var p = HandoverProtocol(id: "photos", kind: .entry, createdEpochMs: 9)
        p.defects = [Defect(id: "d1", photos: ["wall.jpg", "plan.png"], photoEvidence: [PhotoEvidence("wall.jpg", sha256: hash)])]
        try store.save(p)
        return Photographed(root: root, jpeg: jpeg, png: png)
    }

    @Test func aJpegPhotographGoesInRepackedAndComesBackByteForByte() throws {
        let root = try temporaryRoot()
        let fixture = try withPhotographs(root.appendingPathComponent("source"))
        let (source, jpeg, png) = (fixture.root, fixture.jpeg, fixture.png)
        let archive = root.appendingPathComponent("packed.zip")
        try ArchiveIO.export(root: source, to: archive, packer: Deflating())
        let zip = try entries(archive)
        #expect(zip["limen-archive.txt"] == Data("LIMEN_ARCHIVE\nversion=2\n".utf8))
        #expect(zip["jpegxl/photos/wall.jpg"] != nil && zip["photos/photos/wall.jpg"] == nil)
        #expect(zip["photos/photos/plan.png"] == png)
        // The manifest comes last, because only then is it known whether anything was repacked.
        #expect(try Zip.Reader(archive).entries.last?.name == ArchiveIO.manifest)

        let restored = root.appendingPathComponent("restored")
        #expect(try ArchiveIO.importArchive(root: restored, from: archive, packer: Deflating()).imported == 1)
        #expect(try Data(contentsOf: Store(root: restored).photoDir("photos").appendingPathComponent("wall.jpg")) == jpeg)
        #expect(try Data(contentsOf: Store(root: restored).photoDir("photos").appendingPathComponent("plan.png")) == png)

        // A build that cannot unpack refuses the backup whole rather than restore it without its photograph.
        let unable = root.appendingPathComponent("unable")
        #expect(throws: ArchiveError.packedPhotographsUnsupported) { try ArchiveIO.importArchive(root: unable, from: archive, packer: nil) }
        #expect(Store(root: unable).list().isEmpty)
    }

    @Test func aJpegThatWouldNotComeBackExactlyGoesInAsItIsAndTheBackupStaysVersionOne() throws {
        let root = try temporaryRoot()
        let fixture = try withPhotographs(root.appendingPathComponent("source"))
        let (source, jpeg) = (fixture.root, fixture.jpeg)
        let archive = root.appendingPathComponent("unfaithful.zip")
        try ArchiveIO.export(root: source, to: archive, packer: Unfaithful())
        let zip = try entries(archive)
        #expect(zip["limen-archive.txt"] == Data("LIMEN_ARCHIVE\nversion=1\n".utf8))
        #expect(zip.keys.allSatisfy { !$0.hasPrefix("jpegxl/") })
        #expect(zip["photos/photos/wall.jpg"] == jpeg)
        // Version 1 is what 1.2.4 and earlier restore, with no packer at all.
        #expect(try ArchiveIO.importArchive(root: root.appendingPathComponent("restored"), from: archive, packer: nil).imported == 1)
    }

    @Test func aRepackedPhotographThatDoesNotRebuildInstallsNothing() throws {
        let root = try temporaryRoot()
        let source = try withPhotographs(root.appendingPathComponent("source")).root
        let archive = root.appendingPathComponent("packed.zip")
        try ArchiveIO.export(root: source, to: archive, packer: Deflating())
        let restored = root.appendingPathComponent("restored")
        // The record is rejected and counted, as any record whose evidence does not check out is;
        // the rest of the backup still restores, which a thrown error would have prevented.
        let result = try ArchiveIO.importArchive(root: restored, from: archive, packer: Unfaithful())
        #expect(result.imported == 0)
        #expect(result.rejected == 1)
        #expect(Store(root: restored).list().isEmpty)
    }

    /// The old cap was 64 MiB; thirty camera originals weigh 69 MB, so a real record could not be
    /// backed up. The archive itself passes 64 MiB, and so does the one entry.
    @Test func aBackupPastTheOldCapSavesAndRestoresEncryptedAndPlain() throws {
        let root = try temporaryRoot()
        for (run, password) in ["correct horse battery staple", ""].enumerated() {
            let source = Store(root: root.appendingPathComponent("source-\(run)"))
            var p = HandoverProtocol(id: "large", kind: .entry, createdEpochMs: 7)
            p.defects = [Defect(id: "d1", photos: ["wall.jpg"])]
            try source.save(p)
            // A real JPEG with 66 MiB of noise after its end marker: still a decodable photograph,
            // and one that neither Deflate nor the stored form can shrink.
            let photo = source.photoDir("large").appendingPathComponent("wall.jpg")
            _ = try testJPEG(to: photo)
            try appendNoise(to: photo, megabytes: 66, seed: 7 + UInt64(run))
            let archive = root.appendingPathComponent("large-\(run).limen")
            try source.exportArchive(password: password, to: archive, packer: nil)
            #expect(Files.size(archive) > 64 * 1024 * 1024)
            let restored = Store(root: root.appendingPathComponent("restored-\(run)"))
            #expect(try restored.importArchive(password: password, from: archive, packer: nil).imported == 1)
            #expect(try ProtocolIntegrity.fileHash(photo) == ProtocolIntegrity.fileHash(restored.photoDir("large").appendingPathComponent("wall.jpg")))
        }
    }

    /// The device case: a backup larger than the memory the process may use, saved and restored
    /// without ever holding it, measured by the process's own footprint. On the simulator the
    /// available memory is the Mac's, so the test runs only where it is asked for, on the
    /// iPhone, with a 1 GiB file when the real figure is impractical for the phone's storage.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIMEN_LARGE_BACKUP"] == "1"))
    func anEncryptedBackupLargerThanMemorySavesAndRestoresWithoutHoldingIt() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let available = Int64(os_proc_available_memory())
        // LIMEN_LARGE_BACKUP_MB overrides the size for a quicker turn while a growth is chased.
        let megabytes = ProcessInfo.processInfo.environment["LIMEN_LARGE_BACKUP_MB"].flatMap(Int.init)
            ?? min(1024, max(64, Int(available / (1024 * 1024)) + 32))
        let source = Store(root: root.appendingPathComponent("source"))
        var p = HandoverProtocol(id: "heavy", kind: .entry, createdEpochMs: 9)
        p.defects = [Defect(id: "d1", photos: ["wall.jpg"])]
        try source.save(p)
        let photo = source.photoDir("heavy").appendingPathComponent("wall.jpg")
        _ = try testJPEG(to: photo)
        try appendNoise(to: photo, megabytes: megabytes, seed: 9)
        let before = Self.footprint()
        let archive = root.appendingPathComponent("heavy.limen")
        let started = Date()
        try source.exportArchive(password: "heavy password", to: archive, packer: nil)
        let exported = Date().timeIntervalSince(started)
        print("LIMEN_LARGE_BACKUP_PHASE after-export footprint=\(Self.footprint())")
        #expect(Files.size(archive) > Int64(megabytes) * 1024 * 1024)
        let restored = Store(root: root.appendingPathComponent("restored"))
        let restoreStarted = Date()
        #expect(try restored.importArchive(password: "heavy password", from: archive, packer: nil).imported == 1)
        let imported = Date().timeIntervalSince(restoreStarted)
        print("LIMEN_LARGE_BACKUP_PHASE after-import footprint=\(Self.footprint())")
        let after = Self.footprint()
        #expect(try ProtocolIntegrity.fileHash(photo) == ProtocolIntegrity.fileHash(restored.photoDir("heavy").appendingPathComponent("wall.jpg")))
        let grew = Int64(after) - Int64(before)
        print("LIMEN_LARGE_BACKUP megabytes=\(megabytes) availableMB=\(available / (1024 * 1024)) export=\(exported)s restore=\(imported)s footprintBefore=\(before) footprintAfter=\(after) grewMB=\(grew / (1024 * 1024))")
        #expect(grew < 256 * 1024 * 1024, "the footprint grew by \(grew) bytes")
    }

    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// Which step of a restore holds the file, each one alone with the footprint before and after:
    /// on the phone the whole restore grew by the file's size where the simulator did not, and
    /// the steps are the same code, so the probe runs where it is asked for.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIMEN_IMPORT_PROBE_MB"] != nil))
    func whichRestoreStepHoldsTheFile() throws {
        let megabytes = Int(ProcessInfo.processInfo.environment["LIMEN_IMPORT_PROBE_MB"] ?? "") ?? 128
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = Store(root: root.appendingPathComponent("source"))
        var p = HandoverProtocol(id: "probe", kind: .entry, createdEpochMs: 9)
        p.defects = [Defect(id: "d1", photos: ["wall.jpg"])]
        try source.save(p)
        let photoDir = source.photoDir("probe")
        let photo = photoDir.appendingPathComponent("wall.jpg")
        _ = try testJPEG(to: photo)
        try appendNoise(to: photo, megabytes: megabytes, seed: 5)
        let plain = root.appendingPathComponent("plain.zip")
        try ArchiveIO.export(root: source.root, to: plain, packer: nil)
        func probe(_ label: String, _ body: () throws -> Void) rethrows {
            let before = Self.footprint()
            try body()
            print("LIMEN_IMPORT_PROBE \(label) grewMB=\((Int64(Self.footprint()) - Int64(before)) / (1024 * 1024))")
        }
        let reader = try Zip.Reader(plain)
        let entry = try #require(reader.entries.first { $0.name.hasSuffix("wall.jpg") })
        let extracted = root.appendingPathComponent("extracted.jpg")
        try probe("zip-extract") { try reader.extract(entry, to: extracted, space: nil) }
        try probe("zip-extract-freespace") { try reader.extract(entry, to: root.appendingPathComponent("extracted2.jpg"), space: FreeSpace(root)) }
        try probe("copyItem") { try FileManager.default.copyItem(at: extracted, to: root.appendingPathComponent("copied.jpg")) }
        try probe("moveItem") { try FileManager.default.moveItem(at: root.appendingPathComponent("copied.jpg"), to: root.appendingPathComponent("moved.jpg")) }
        try probe("readable") { _ = PhotoDecode.readable(extracted) }
        try probe("fileHash") { _ = try ProtocolIntegrity.fileHash(extracted) }
        try probe("unreadable") { _ = EvidenceValidation.unreadable(p, photoDir: photoDir, signatureDir: source.signatureDir("probe")) }
        try probe("missingEvidence") { _ = ProtocolIntegrity.missingEvidence(p, photoDir: photoDir, signatureDir: source.signatureDir("probe")) }
        try probe("import-plain") { _ = try ArchiveIO.importArchive(root: root.appendingPathComponent("restored"), from: plain, packer: nil) }
        let sealed = root.appendingPathComponent("sealed.limen")
        try source.exportArchive(password: "probe", to: sealed, packer: nil)
        try probe("import-sealed") { _ = try Store(root: root.appendingPathComponent("restored2")).importArchive(password: "probe", from: sealed, packer: nil) }
    }

    /// ZIP64 wherever a size, an offset or a count needs it: the writer is driven past a lowered
    /// threshold so the records appear on a small archive, the reader takes them back, and the
    /// file is left for Python's zipfile to read as the second implementation.
    @Test func zip64RecordsAreWrittenPastTheThresholdAndReadBack() throws {
        let root = try temporaryRoot()
        let archive = root.appendingPathComponent("zip64.zip")
        let writer = try Zip.Writer(to: archive, zip64Threshold: 1000)
        let text = Data(String(repeating: "handover ", count: 300).utf8)
        try writer.put("protocols/a.json", bytes: text)
        try writer.put("photos/a/x.jpg", bytes: Data((0..<2500).map { UInt8($0 & 0xFF) }))
        try writer.put(ArchiveIO.manifest, bytes: Data(ArchiveIO.marker.utf8))
        try writer.finish()
        let bytes = try Data(contentsOf: archive)
        #expect(bytes.lastRange(of: Data([0x50, 0x4B, 0x06, 0x06])) != nil, "a ZIP64 end record")
        #expect(bytes.lastRange(of: Data([0x50, 0x4B, 0x06, 0x07])) != nil, "its locator")
        let reader = try Zip.Reader(archive)
        #expect(reader.entries.map(\.name) == ["protocols/a.json", "photos/a/x.jpg", ArchiveIO.manifest])
        #expect(try reader.read(reader.entries[0]) == text)
        #expect(try reader.read(reader.entries[1]) == Data((0..<2500).map { UInt8($0 & 0xFF) }))
        #expect(reader.entries[1].method == 0 && reader.entries[0].method == 8)
        print("LIMEN_ZIP64_OUTPUT \(archive.path)")
    }

    @Test func aZip64ArchiveWrittenByPythonIsReadWithItsLocalHeaderFields() throws {
        let fixture = try #require(Bundle(for: CompatibilityMarker.self).url(forResource: "Compatibility", withExtension: nil)).appendingPathComponent("zip64-python.zip")
        let reader = try Zip.Reader(fixture)
        #expect(reader.entries.map(\.name) == ["limen-archive.txt", "protocols/p.json", "photos/p/wall.jpg"])
        #expect(try reader.read(reader.entries[0]) == Data("LIMEN_ARCHIVE\nversion=1\n".utf8))
        #expect(try reader.read(reader.entries[1]) == Data(#"{"schema":2,"id":"p","kind":"Entry","createdEpochMs":1}"#.utf8))
        #expect(try reader.read(reader.entries[2]) == Data(Array(repeating: Array(0...255).map(UInt8.init), count: 40).flatMap { $0 }))
        // And installs as a backup, local ZIP64 fields and all.
        let restored = Store(root: try temporaryRoot())
        #expect(try restored.importArchive(password: "", from: fixture, packer: nil).imported == 1)
    }

    /// A streamed entry larger than one piece inflates to the bytes it was given, and a directory
    /// that lies about the size is refused before the inflated bytes pass it.
    @Test func streamedEntriesInflateInPiecesAndALyingSizeIsRefused() throws {
        let root = try temporaryRoot()
        let archive = root.appendingPathComponent("stream.zip")
        let writer = try Zip.Writer(to: archive)
        let text = Data(String(repeating: "piece by piece ", count: 60_000).utf8)
        try writer.put("protocols/a.json", bytes: text)
        try writer.finish()
        let reader = try Zip.Reader(archive)
        #expect(reader.entries[0].compressedSize < Int64(text.count) / 10)
        let out = root.appendingPathComponent("out.json")
        try reader.extract(reader.entries[0], to: out, space: FreeSpace(root))
        #expect(try Data(contentsOf: out) == text)
        // Both headers agree on the lie, so the directory passes and the reader meets it while
        // inflating: it stops at the declared size instead of inflating the rest into memory.
        var lying = try Data(contentsOf: archive)
        let central = try #require(lying.lastRange(of: Data([0x50, 0x4B, 0x01, 0x02]))).lowerBound
        lying.replaceSubrange((central + 24)..<(central + 28), with: [0x10, 0x00, 0x00, 0x00])
        lying.replaceSubrange(22..<26, with: [0x10, 0x00, 0x00, 0x00])
        let liar = root.appendingPathComponent("liar.zip")
        try lying.write(to: liar)
        let lied = try Zip.Reader(liar)
        #expect(throws: Zip.ZipError.self) { try lied.read(lied.entries[0]) }
    }
}

private final class CompatibilityMarker: NSObject {}
