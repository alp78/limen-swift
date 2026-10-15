import Foundation
import Testing
@testable import LimenKit

private final class CompatibilityBundle: NSObject {}

@Suite struct CrossPlatformTests {
    private func fixtures() throws -> URL {
        try #require(Bundle(for: CompatibilityBundle.self).url(forResource: "Compatibility", withExtension: nil))
    }

    @Test func androidCanonicalBytesAndFingerprintsAgreeForEveryRecordStage() throws {
        let fixtures = try fixtures()
        for id in ["draft", "final", "delivered", "amendment"] {
            let bytes = try Data(contentsOf: fixtures.appendingPathComponent("\(id).stored.json"))
            let p = try ProtocolJSON.decode(bytes)
            let canonical = try Data(contentsOf: fixtures.appendingPathComponent("\(id).canonical.json"))
            #expect(Data(ProtocolJSON.encode(p, encodeDefaults: true).compact.utf8) == canonical, "canonical bytes for \(id)")
            #expect(Data(Store.fileText(p).utf8) == bytes, "stored bytes for \(id)")
            let fingerprint = try ProtocolIntegrity.fingerprint(p, photoDir: fixtures.appendingPathComponent("assets"), signatureDir: fixtures.appendingPathComponent("assets"))
            #expect(fingerprint == readText(fixtures.appendingPathComponent("\(id).fingerprint.txt")))
            #expect(p.parties.count == 3)
            #expect(p.details.scopeNotes.count == 2)
            #expect(p.defects.first?.participantPositions.count == 2)
            #expect(p.deposit.kind == .unknown)
        }
    }

    @Test func androidPlainAndEncryptedArchivesRestoreAndReexportForJvmVerification() throws {
        let fixtures = try fixtures(), root = try temporaryRoot()
        for name in ["android.zip", "android.limen", "jvm-return.zip", "jvm-return.limen"] {
            let store = Store(root: root.appendingPathComponent(name))
            let result = try store.importArchive(password: "päss 🔐", from: fixtures.appendingPathComponent(name))
            #expect(result == ArchiveImportResult(imported: 4, skippedExisting: 0, rejected: 0))
            for p in store.list() {
                #expect(ProtocolJSON.encode(p, encodeDefaults: true).compact == readText(fixtures.appendingPathComponent("\(p.id).canonical.json")))
                #expect(try ProtocolIntegrity.fingerprint(p, photoDir: store.photoDir(p.id), signatureDir: store.signatureDir(p.id)) == readText(fixtures.appendingPathComponent("\(p.id).fingerprint.txt")))
            }
            let delivered = try #require(store.load("delivered"))
            let retained = try #require(store.retainedExport(delivered.id, name: "retained.pdf"))
            #expect(try Data(contentsOf: retained) == Data(contentsOf: fixtures.appendingPathComponent("assets/retained.pdf")))
            #expect(!FileManager.default.fileExists(atPath: store.photoDir("draft").appendingPathComponent("retained.pdf").path))
            if name == "android.limen" {
                try store.exportArchive(password: "", to: root.appendingPathComponent("swift.zip"))
                try store.exportArchive(password: "päss 🔐", to: root.appendingPathComponent("swift.limen"))
            }
        }
        print("LIMEN_SWIFT_COMPAT_OUTPUT \(root.path)")
    }
    @Test func deterministicJvmEnvelopeVectorMatchesSwiftWithUnicodePasswordAndChunkBoundaries() throws {
        let fixtures = try fixtures()
        let vector = try Data(contentsOf: fixtures.appendingPathComponent("crypto-vector.limen"))
        let header = Data(vector.prefix(38)), salt = Data(vector[10..<26]), iv = Data(vector[26..<38])
        let key = try ArchiveCrypto.derive(password: "päss 🔐", salt: salt)
        #expect(key.map { String(format: "%02X", $0) }.joined() == readText(fixtures.appendingPathComponent("crypto-key.hex")))
        let stream = try AESGCMStream(key: key, iv: iv, aad: header)
        let plain = Data((0..<700_003).map { UInt8(($0 * 31 + 7) & 255) })
        var ciphertext = Data()
        for chunk in plain.chunked(by: 256 * 1024) { ciphertext.append(try stream.encrypt(chunk)) }
        #expect(header + ciphertext + stream.finalizeEncryption() == vector)
    }

    @Test func originalHeicBytesDecodeWithoutReencoding() throws {
        let file = try fixtures().appendingPathComponent("assets/wall.heic")
        let before = try ProtocolIntegrity.fileHash(file)
        #expect(try EvidenceValidation.validatePhoto(file) == "image/heic")
        #expect(PhotoDecode.sampled(file, targetWidth: 256) != nil)
        #expect(try ProtocolIntegrity.fileHash(file) == before)
    }

}
