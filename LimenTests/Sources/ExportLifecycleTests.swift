import Foundation
import ImageIO
import LimenKit
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Limen

private actor RetainedExportBarrier {
    let name = "lifecycle-\(UUID().uuidString).pdf"
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var finishWaiter: CheckedContinuation<Void, Never>?

    func render(_ record: HandoverProtocol, store: Store) async throws -> ExportCopy {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { finishWaiter = $0 }
        let pdf = store.exportDir(record.id).appendingPathComponent(name)
        let data = Data("Export operation fixture".utf8)
        for directory in [pdf.deletingLastPathComponent(), Exports.folder] {
            try data.write(to: directory.appendingPathComponent(name))
            try Data("<p>Export operation fixture</p>".utf8).write(to: directory.appendingPathComponent(name).deletingPathExtension().appendingPathExtension("html"))
        }
        return ExportCopy(uri: "foreign://untrusted-location", name: name, bytes: Int64(data.count), language: "En",
                          deliveryRevision: record.deliveryRevision, epochMs: 100,
                          companionUri: "foreign://untrusted-companion", sha256: try ProtocolIntegrity.fileHash(pdf))
    }

    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish() { finishWaiter?.resume(); finishWaiter = nil }
}

@Suite @MainActor struct ExportLifecycleTests {
    private func model() throws -> LimenModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("limen-export-lifecycle-\(UUID().uuidString)")
        let prefs = try #require(UserDefaults(suiteName: "limen-export-lifecycle-\(UUID().uuidString)"))
        return LimenModel(prefs: prefs, root: root)
    }

    private func finalized(_ id: String, fingerprint: String = "original-fingerprint") -> HandoverProtocol {
        var record = HandoverProtocol(id: id, kind: .entry, createdEpochMs: 1)
        record.finalizedEpochMs = 1
        record.evidenceFingerprint = fingerprint
        return record
    }

    private func expectAbsent(_ name: String, model: LimenModel, id: String) {
        let directory = model.store.root.appendingPathComponent("exports").appendingPathComponent(id)
        for folder in [directory, Exports.folder] {
            let pdf = folder.appendingPathComponent(name)
            #expect(!FileManager.default.fileExists(atPath: pdf.path))
            #expect(!FileManager.default.fileExists(atPath: pdf.deletingPathExtension().appendingPathExtension("html").path))
        }
    }

    @Test func deletedRecordCannotBeResurrectedByALateExport() async throws {
        let model = try model()
        model.setActiveProtocol(finalized("deleted"))
        let gate = RetainedExportBarrier()
        model.exportRenderer = { record, _, store in try await gate.render(record, store: store) }
        model.exportPdf()
        await gate.waitForStart()
        model.deleteProtocol("deleted")
        let unrelated = model.store.exportDir("deleted").appendingPathComponent("unrelated.txt")
        try Data("Keep this other operation".utf8).write(to: unrelated)
        await gate.finish()
        await model.exportTask?.value
        #expect(model.store.load("deleted") == nil)
        #expect(model.working?.exportHistory.isEmpty == true)
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "Keep this other operation")
        expectAbsent(gate.name, model: model, id: "deleted")
    }

    @Test func replacementWithTheSameIdCannotReceiveAnEarlierFingerprintExport() async throws {
        let model = try model()
        model.setActiveProtocol(finalized("replaced"))
        let gate = RetainedExportBarrier()
        model.exportRenderer = { record, _, store in try await gate.render(record, store: store) }
        model.exportPdf()
        await gate.waitForStart()
        model.store.delete("replaced")
        model.setActiveProtocol(finalized("replaced", fingerprint: "replacement-fingerprint"))
        #expect(model.flush())
        await gate.finish()
        await model.exportTask?.value
        let saved = try #require(model.store.load("replaced"))
        #expect(saved.evidenceFingerprint == "replacement-fingerprint")
        #expect(saved.exportHistory.isEmpty)
        #expect(model.working?.exportHistory.isEmpty == true)
        expectAbsent(gate.name, model: model, id: "replaced")
    }

    @Test func documentIntakeUsesDecodedMimeForTheRetainedExtension() async throws {
        let model = try model()
        model.setActiveProtocol(HandoverProtocol(id: "document", kind: .entry, createdEpochMs: 1))
        let source = model.store.root.appendingPathComponent("misleading.jpg")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        }
        let destination = try #require(CGImageDestinationCreateWithURL(source as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(image.cgImage), nil)
        #expect(CGImageDestinationFinalize(destination))
        await model.importDocument(source: source, kind: .other)?.value
        let document = try #require(model.working?.details.attachments.first)
        #expect(document.mime == "image/tiff")
        #expect((document.file as NSString).pathExtension == UTType.tiff.preferredFilenameExtension)
        #expect(try Data(contentsOf: model.store.photoDir("document").appendingPathComponent(document.file)) == Data(contentsOf: source))
        #expect(model.evidenceError == nil)
    }
}
