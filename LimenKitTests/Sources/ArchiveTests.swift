import CryptoKit
import Foundation
import Testing
@testable import LimenKit

@Suite struct ArchiveTests {
    private let password = "correct horse battery staple"

    private func record(_ id: String, _ kind: Kind, _ created: Int64) -> HandoverProtocol {
        HandoverProtocol(id: id, kind: kind, createdEpochMs: created)
    }

    @Test func roundTripRestoresProtocolAndEvidenceWithoutOverwriting() throws {
        let root = try temporaryRoot()
        let source = Store(root: root.appendingPathComponent("source"))
        var p = record("p1", .entry, 1)
        p.defects = [Defect(id: "d1", photos: ["wall.jpg"])]
        try source.save(p)
        try writeText("original evidence", to: source.photoDir("p1").appendingPathComponent("wall.jpg"))
        let archive = root.appendingPathComponent("backup.limen")
        try source.exportArchive(password: password, to: archive)

        let restored = Store(root: root.appendingPathComponent("restored"))
        let first = try restored.importArchive(password: password, from: archive)
        let second = try restored.importArchive(password: password, from: archive)
        #expect(first == ArchiveImportResult(imported: 1, skippedExisting: 0, rejected: 0))
        #expect(second == ArchiveImportResult(imported: 0, skippedExisting: 1, rejected: 0))
        #expect(restored.load("p1") == p)
        #expect(readText(restored.photoDir("p1").appendingPathComponent("wall.jpg")) == "original evidence")
    }

    @Test func restoreRejectsARecordWhoseEvidenceIsMissing() throws {
        let root = try temporaryRoot()
        let source = Store(root: root.appendingPathComponent("source"))
        var p = record("p2", .exit, 2)
        p.defects = [Defect(id: "d2", photos: ["missing.jpg"])]
        try source.save(p)
        let archive = root.appendingPathComponent("backup.limen")
        try source.exportArchive(password: password, to: archive)
        let restored = Store(root: root.appendingPathComponent("restored"))
        #expect(try restored.importArchive(password: password, from: archive).rejected == 1)
        #expect(restored.list().isEmpty)
    }

    @Test func restoreRejectsPathTraversal() throws {
        let root = try temporaryRoot()
        let archive = root.appendingPathComponent("evil.zip")
        let zip = try Zip.Writer(to: archive)
        try zip.put("../outside", bytes: Data([1]))
        try zip.finish()
        let restored = Store(root: root.appendingPathComponent("restored"))
        #expect(throws: ArchiveError.self) { try restored.importArchive(password: password, from: archive) }
    }

    @Test func exportIgnoresStrayFilesThatAreNotArchiveEntries() throws {
        let root = try temporaryRoot()
        let sourceRoot = root.appendingPathComponent("source")
        let source = Store(root: sourceRoot)
        try source.save(record("p3", .entry, 3))
        try writeText("partial", to: sourceRoot.appendingPathComponent("protocols/unfinished.tmp"))
        try writeText("orphan", to: sourceRoot.appendingPathComponent("photos/not an id/unexpected file.jpg"))
        let archive = root.appendingPathComponent("backup.limen")
        try source.exportArchive(password: password, to: archive)
        let restored = Store(root: root.appendingPathComponent("restored"))
        #expect(try restored.importArchive(password: password, from: archive).imported == 1)
        #expect(restored.list().map(\.id) == ["p3"])
    }

    @Test func encryptedBackupDoesNotExposeProtocolOrEvidenceText() throws {
        let root = try temporaryRoot()
        let source = Store(root: root.appendingPathComponent("source"))
        var p = record("private-record", .entry, 4)
        p.remarks = "private reservation phrase"
        try source.save(p)
        let archive = root.appendingPathComponent("backup.limen")
        try source.exportArchive(password: password, to: archive)
        let bytes = try Data(contentsOf: archive)
        #expect(bytes.prefix(9) == Data("LIMENSAFE".utf8))
        let encoded = String(decoding: bytes, as: UTF8.self)
        #expect(!encoded.contains("private-record"))
        #expect(!encoded.contains("private reservation phrase"))
    }

    @Test func wrongPasswordCannotRestoreEncryptedBackup() throws {
        let root = try temporaryRoot()
        let source = Store(root: root.appendingPathComponent("source"))
        try source.save(record("p4", .entry, 5))
        let archive = root.appendingPathComponent("backup.limen")
        try source.exportArchive(password: password, to: archive)
        let restored = Store(root: root.appendingPathComponent("restored"))
        #expect(throws: ArchiveError.wrongPassword) { try restored.importArchive(password: "wrong password", from: archive) }
        #expect(restored.list().isEmpty)
    }

    @Test func legacyPlainZipRemainsImportable() throws {
        let root = try temporaryRoot()
        let sourceRoot = root.appendingPathComponent("source")
        let source = Store(root: sourceRoot)
        try source.save(record("legacy", .exit, 6))
        let archive = root.appendingPathComponent("legacy.zip")
        try ArchiveIO.export(root: sourceRoot, to: archive)
        let restored = Store(root: root.appendingPathComponent("restored"))
        #expect(try restored.importArchive(password: "unused", from: archive).imported == 1)
    }

    @Test func emptyPasswordWritesAPlainArchiveThatRestoresWithoutOne() throws {
        let root = try temporaryRoot()
        let sourceRoot = root.appendingPathComponent("source-open")
        let source = Store(root: sourceRoot)
        try source.save(record("open", .exit, 7))
        let archive = root.appendingPathComponent("open.limen")
        try source.exportArchive(password: "", to: archive)

        // Plain means plain: a zip signature, not the LIMENSAFE envelope.
        let head = try Data(contentsOf: archive).prefix(2)
        #expect(head == Data("PK".utf8))
        let restored = Store(root: root.appendingPathComponent("restored-open"))
        #expect(try restored.importArchive(password: "", from: archive).imported == 1)
    }

    /// The cipher against CryptoKit at the REAL envelope's associated data length. The header is
    /// magic(9) + version(1) + salt(16) + iv(12) = 38 bytes, which is two whole GHASH blocks and a
    /// 6 byte remainder. Every length that is not a multiple of 16 has to appear here: a test whose
    /// associated data happens to be block-aligned cannot see a dropped remainder.
    @Test func theStreamingCipherAgreesWithCryptoKitAtEveryAssociatedDataLength() throws {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let iv = Data((0..<12).map { UInt8($0 * 7 + 1) })
        let plain = Data((0..<5000).map { UInt8(($0 * 31) & 0xFF) })
        for aadLength in [0, 1, 15, 16, 17, 31, 38, 64, 100] {
            let aad = Data((0..<aadLength).map { UInt8(($0 * 13 + 5) & 0xFF) })
            let sealed = try AES.GCM.seal(plain, using: key, nonce: try AES.GCM.Nonce(data: iv), authenticating: aad)
            let stream = try AESGCMStream(key: keyData, iv: iv, aad: aad)
            var cipher = Data()
            for chunk in plain.chunked(by: 1000) { cipher.append(try stream.encrypt(chunk)) }
            #expect(stream.finalizeEncryption() == sealed.tag, "tag at aad length \(aadLength)")
        }
    }

    /// The streaming cipher against CryptoKit's own AES-GCM, both ways, so the tag it writes is
    /// the tag Java's AES/GCM/NoPadding checks.
    @Test func theStreamingCipherAgreesWithCryptoKit() throws {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let iv = Data((0..<12).map { UInt8($0 * 7 + 1) })
        let aad = Data("LIMENSAFE header".utf8)
        for length in [0, 1, 15, 16, 17, 1000, 70_000] {
            let plain = Data((0..<length).map { UInt8(($0 * 31) & 0xFF) })
            let sealed = try AES.GCM.seal(plain, using: key, nonce: try AES.GCM.Nonce(data: iv), authenticating: aad)
            let stream = try AESGCMStream(key: keyData, iv: iv, aad: aad)
            var cipher = Data()
            for chunk in plain.chunked(by: 1000) { cipher.append(try stream.encrypt(chunk)) }
            let tag = stream.finalizeEncryption()
            #expect(cipher == sealed.ciphertext, "ciphertext at \(length)")
            #expect(tag == sealed.tag, "tag at \(length)")

            let back = try AESGCMStream(key: keyData, iv: iv, aad: aad)
            var opened = Data()
            for chunk in sealed.ciphertext.chunked(by: 777) { opened.append(try back.decrypt(chunk)) }
            #expect(back.finalizeDecryption(tag: sealed.tag))
            #expect(opened == plain)
        }
    }

    @Test func theZipWriterAndReaderRoundTripAndInflate() throws {
        let root = try temporaryRoot()
        let archive = root.appendingPathComponent("a.zip")
        let zip = try Zip.Writer(to: archive)
        let text = Data(String(repeating: "handover ", count: 2000).utf8)
        try zip.put("protocols/a.json", bytes: text)
        try zip.put("photos/a/x.jpg", bytes: Data([1, 2, 3]))
        try zip.finish()
        let reader = try Zip.Reader(archive)
        #expect(reader.entries.map(\.name) == ["protocols/a.json", "photos/a/x.jpg"])
        #expect(reader.entries[0].method == 8)
        #expect(reader.entries[0].compressedSize < 1000)
        #expect(try reader.read(reader.entries[0]) == text)
        #expect(try reader.read(reader.entries[1]) == Data([1, 2, 3]))
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }
}

extension Data {
    func chunked(by size: Int) -> [Data] {
        guard !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map { self[startIndex + $0..<Swift.min(startIndex + $0 + size, endIndex)] }
    }
}
