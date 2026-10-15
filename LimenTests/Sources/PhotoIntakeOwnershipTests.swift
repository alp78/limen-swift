import Foundation
import LimenKit
import Testing
import UIKit
@testable import Limen

/// The enclosing task is MainActor-bound, so changing the working record before the first await
/// deterministically changes the owner before intake can merge its detached copy result.
@Suite @MainActor struct PhotoIntakeOwnershipTests {
    private let ownerId = "shared-room"

    private func model() throws -> LimenModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("limen-photo-owner-\(UUID().uuidString)")
        let prefs = try #require(UserDefaults(suiteName: "limen-photo-owner-\(UUID().uuidString)"))
        return LimenModel(prefs: prefs, root: root)
    }

    private func record(_ id: String) -> HandoverProtocol {
        var value = HandoverProtocol(id: id, kind: .entry, createdEpochMs: 1)
        value.rooms = [Room(id: ownerId, kind: .room)]
        return value
    }

    private func source(in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("intake-\(UUID().uuidString).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 16), format: format).pngData { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
            UIColor.yellow.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 7, height: 5))
        }
        try data.write(to: file)
        return file
    }

    private func files(_ directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
    }

    @Test(arguments: [false, true])
    func sameOwnerIdInAnotherRecordCannotReceiveAnEarlierPhoto(amendment: Bool) async throws {
        let model = try model()
        let original = record("original")
        model.setActiveProtocol(original)
        let source = try source(in: model.store.root)
        let task = try #require(model.intakePhoto(ownerId: ownerId, source: source, photoSource: .gallery, kind: .room))
        var other = record(amendment ? "amendment" : "other")
        if amendment { other.amendedFromId = original.id; other.amendedFromFingerprint = "original-fingerprint" }
        model.setActiveProtocol(other)
        await task.value
        #expect(model.working == other)
        #expect(try files(model.store.photoDir(original.id)).isEmpty)
        #expect(try files(model.store.photoDir(other.id)).isEmpty)
        #expect(FileManager.default.fileExists(atPath: source.path), "An external picker input belongs to its provider")
        #expect(model.evidenceError == nil)
    }

    @Test func removedOwnerCannotReceiveOrStrandAnIncomingPhoto() async throws {
        let model = try model()
        model.setActiveProtocol(record("removed-owner"))
        let source = try source(in: model.store.root)
        let task = try #require(model.intakePhoto(ownerId: ownerId, source: source, photoSource: .gallery, kind: .room))
        model.edit { var next = $0; next.rooms.removeAll(); return next }
        await task.value
        #expect(model.working?.rooms.isEmpty == true)
        #expect(model.working?.details.roomPhotos.isEmpty == true)
        #expect(try files(model.store.photoDir("removed-owner")).isEmpty)
    }

    @Test func finalizationBeforeIntakeCompletesRejectsTheNewEvidence() async throws {
        let model = try model()
        model.setActiveProtocol(record("frozen"))
        let source = try source(in: model.store.root)
        let task = try #require(model.intakePhoto(ownerId: ownerId, source: source, photoSource: .gallery, kind: .room))
        var frozen = try #require(model.working)
        frozen.finalizedEpochMs = 2
        frozen.evidenceFingerprint = "frozen-fingerprint"
        model.setActiveProtocol(frozen)
        await task.value
        #expect(model.working == frozen)
        #expect(try files(model.store.photoDir(frozen.id)).isEmpty)
        #expect(model.pendingEdit == nil)
    }

    @Test func privateCaptureCleanupLeavesEveryOtherOperationAlone() async throws {
        let model = try model()
        model.setActiveProtocol(record("capture"))
        let owned = try source(in: AppFiles.captures)
        let unrelated = try source(in: AppFiles.captures)
        let unrelatedBytes = try Data(contentsOf: unrelated)
        defer {
            try? FileManager.default.removeItem(at: owned)
            try? FileManager.default.removeItem(at: unrelated)
        }
        let task = try #require(model.intakePhoto(ownerId: ownerId, source: owned, photoSource: .camera, kind: .room))
        model.setActiveProtocol(record("switched"))
        await task.value
        #expect(!FileManager.default.fileExists(atPath: owned.path))
        #expect(try Data(contentsOf: unrelated) == unrelatedBytes)
        #expect(try files(model.store.photoDir("capture")).isEmpty)
        #expect(model.working?.details.roomPhotos.isEmpty == true)
    }

    @Test func successfulIntakeRetainsExactBytesHashAndSeparateCaptureMetadata() async throws {
        let model = try model()
        model.setActiveProtocol(record("success"))
        let source = try source(in: model.store.root)
        let originalBytes = try Data(contentsOf: source)
        let hash = try ProtocolIntegrity.fileHash(source)
        let task = try #require(model.intakePhoto(ownerId: ownerId, source: source, photoSource: .gallery, kind: .room))
        await task.value
        let evidence = try #require(model.working?.details.roomPhotos[ownerId]?.first)
        #expect(try Data(contentsOf: model.store.photoDir("success").appendingPathComponent(evidence.file)) == originalBytes)
        #expect(evidence.sha256 == hash)
        #expect(evidence.source == .gallery)
        #expect(evidence.capturedEpochMs == 0)
        #expect(evidence.importedEpochMs > 0)
        #expect(model.flush())
        #expect(model.store.load("success")?.details.roomPhotos[ownerId]?.first == evidence)
    }
}
