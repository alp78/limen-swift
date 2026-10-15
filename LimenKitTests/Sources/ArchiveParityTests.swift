import Foundation
import Testing
@testable import LimenKit

@Suite struct ArchiveParityTests {
    @Test func scopedArchivesIncludeOnlyReferencedEvidenceAttachmentsAndRetainedCopies() throws {
        let root = try temporaryRoot(); let source = Store(root: root.appendingPathComponent("source"))
        var p = HandoverProtocol(id: "selected", kind: .entry, createdEpochMs: 1)
        let photo = source.photoDir(p.id).appendingPathComponent("meter.png")
        _ = try testImage(to: photo)
        p.details.readings = [MeterReading(id: "meter", photos: [PhotoEvidence("meter.png", sha256: try ProtocolIntegrity.fileHash(photo))])]
        let pdf = source.photoDir(p.id).appendingPathComponent("lease.pdf")
        let pdfBytes = try testPDF(to: pdf)
        p.details.attachments = [SupportingDocument(id: "lease", kind: .lease, file: "lease.pdf", sha256: try ProtocolIntegrity.fileHash(pdf), bytes: Int64(pdfBytes.count))]
        let retained = source.exportDir(p.id).appendingPathComponent("copy.pdf")
        try pdfBytes.write(to: retained)
        try writeText("<!doctype html><html lang='en'><title>copy</title><p>retained</p></html>", to: source.exportDir(p.id).appendingPathComponent("copy.html"))
        p.exportHistory = [ExportCopy(uri: "content://foreign/31", name: "copy.pdf", bytes: Int64(pdfBytes.count), language: "En", deliveryRevision: 0, epochMs: 2, companionUri: "content://foreign/32", sha256: try ProtocolIntegrity.fileHash(retained))]
        try source.save(p)
        try source.save(HandoverProtocol(id: "private", kind: .entry, createdEpochMs: 2))
        try writeText("deleted private original", to: source.photoDir(p.id).appendingPathComponent("orphan.jpg"))
        try writeText("untracked export", to: source.exportDir(p.id).appendingPathComponent("orphan.pdf"))
        let archive = root.appendingPathComponent("scoped.zip")
        try source.exportArchive(password: "", to: archive, protocolIds: [p.id])
        let entries = try Zip.Reader(archive).entries.map(\.name)
        #expect(Set(entries) == [ArchiveIO.manifest, "protocols/selected.json", "photos/selected/meter.png", "photos/selected/lease.pdf", "exports/selected/copy.pdf", "exports/selected/copy.html"])
        let restored = Store(root: root.appendingPathComponent("restored"))
        #expect(try restored.importArchive(password: "", from: archive).imported == 1)
        #expect(restored.load("private") == nil)
        #expect(try Data(contentsOf: #require(restored.retainedExport(p.id, name: "copy.pdf"))) == pdfBytes)
        #expect(restored.retainedExport(p.id, name: "../copy.pdf") == nil)
    }

    @Test func explicitRepairQuarantinesCorruptOriginalAndPreservesHealthyRecords() throws {
        let root = try temporaryRoot(); let source = Store(root: root.appendingPathComponent("source"))
        let p = HandoverProtocol(id: "p", kind: .entry, createdEpochMs: 1)
        try source.save(p)
        let archive = root.appendingPathComponent("backup.zip")
        try source.exportArchive(password: "", to: archive)
        let restored = Store(root: root.appendingPathComponent("restored"))
        try restored.save(p)
        let target = restored.root.appendingPathComponent("protocols/p.json")
        try writeText("damaged original", to: target)
        #expect(try restored.importArchive(password: "", from: archive) == ArchiveImportResult(imported: 0, skippedExisting: 1, rejected: 0, repairable: 1))
        #expect(readText(target) == "damaged original")
        #expect(try restored.importArchive(password: "", from: archive, repairCorrupt: true).repaired == 1)
        let preserved = FileManager.default.enumerator(at: restored.root.appendingPathComponent("recovery/p"), includingPropertiesForKeys: nil)
        #expect((preserved?.allObjects as? [URL] ?? []).contains { readText($0) == "damaged original" })
        #expect(restored.load(p.id) == p)
        #expect(try restored.importArchive(password: "", from: archive, repairCorrupt: true).skippedExisting == 1)
    }

    @Test func authenticationFailureInstallsNothing() throws {
        let root = try temporaryRoot(); let source = Store(root: root.appendingPathComponent("source"))
        try source.save(HandoverProtocol(id: "p", kind: .entry, createdEpochMs: 1))
        let archive = root.appendingPathComponent("backup.limen")
        try source.exportArchive(password: "päss 🔐", to: archive)
        let original = try Data(contentsOf: archive)
        for tail in [0, 1, 16] {
            var corrupted = tail == 0 ? original : Data(original.dropLast(tail))
            if tail == 0 { corrupted[corrupted.count - 1] ^= 1 }
            let input = root.appendingPathComponent("tampered-\(tail).limen")
            try corrupted.write(to: input)
            let destination = Store(root: root.appendingPathComponent("destination-\(tail)"))
            #expect(throws: ArchiveError.self) { try destination.importArchive(password: "päss 🔐", from: input) }
            #expect(destination.catalogue().records.isEmpty)
            #expect(destination.catalogue().unreadable.isEmpty)
        }
    }

    @Test func centralSizesOffsetsNamesAndSymlinksAreValidatedBeforeAllocation() throws {
        let root = try temporaryRoot(), valid = root.appendingPathComponent("valid.zip")
        let writer = try Zip.Writer(to: valid); try writer.put("protocols/p.json", bytes: Data("{}".utf8)); try writer.finish()
        let original = try Data(contentsOf: valid)
        let central = try #require(original.lastRange(of: Data([0x50, 0x4B, 0x01, 0x02]))).lowerBound
        let end = try #require(original.lastRange(of: Data([0x50, 0x4B, 0x05, 0x06]))).lowerBound
        let changes: [(Int, [UInt8])] = [
            (central + 24, [0xFF, 0xFF, 0xFF, 0x7F]),
            (central + 20, [0xFF, 0xFF, 0xFF, 0x7F]),
            (end + 12, [0xFF, 0xFF, 0xFF, 0x7F]),
            (central + 42, [0xFF, 0xFF, 0xFF, 0x7F]),
            (central + 40, [0xFF, 0xA1]),
            (30, [UInt8(ascii: "x")]),
        ]
        for (index, change) in changes.enumerated() {
            var bytes = original; bytes.replaceSubrange(change.0..<(change.0 + change.1.count), with: change.1)
            let input = root.appendingPathComponent("bad-\(index).zip"); try bytes.write(to: input)
            #expect(throws: (any Error).self) { _ = try Zip.Reader(input) }
        }
    }
    @Test func missingRetainedCopiesCanBeExplicitlyRepairedAndMissingCompanionsBlockBackup() throws {
        let root = try temporaryRoot(); let source = Store(root: root.appendingPathComponent("source"))
        var p = HandoverProtocol(id: "p", kind: .entry, createdEpochMs: 1)
        let pdf = source.exportDir(p.id).appendingPathComponent("copy.pdf")
        let bytes = try testPDF(to: pdf)
        p.exportHistory = [ExportCopy(uri: "copy.pdf", name: "copy.pdf", bytes: Int64(bytes.count), language: "En",
            deliveryRevision: 1, epochMs: 2, companionUri: "copy.html", sha256: try ProtocolIntegrity.fileHash(pdf))]
        try source.save(p)
        let archive = root.appendingPathComponent("copies.zip")
        #expect(throws: ArchiveError.missingExport("p")) { try source.exportArchive(password: "", to: archive) }
        try writeText("<html lang='en'><title>Exact companion</title></html>", to: source.exportDir(p.id).appendingPathComponent("copy.html"))
        try source.exportArchive(password: "", to: archive)
        let destination = Store(root: root.appendingPathComponent("destination"))
        #expect(try destination.importArchive(password: "", from: archive).imported == 1)
        try FileManager.default.removeItem(at: destination.exportDir(p.id).appendingPathComponent("copy.pdf"))
        #expect(try destination.importArchive(password: "", from: archive).repairable == 1)
        #expect(try destination.importArchive(password: "", from: archive, repairCorrupt: true).repaired == 1)
        #expect(try Data(contentsOf: #require(destination.retainedExport(p.id, name: "copy.pdf"))) == bytes)
    }

}
