import Foundation
import LimenKit
import Testing
import UIKit
@testable import Limen

private actor ExportBarrier {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var finishWaiter: CheckedContinuation<Void, Never>?
    func render(_ record: HandoverProtocol) async -> ExportCopy {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { finishWaiter = $0 }
        return ExportCopy(uri: "exports/\(record.id)/copy.pdf", name: "copy.pdf", bytes: 1, language: "En",
                          deliveryRevision: record.deliveryRevision, epochMs: 100)
    }
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func finish() { finishWaiter?.resume(); finishWaiter = nil }
}

@Suite @MainActor struct RemediationModelTests {
    private func model() throws -> LimenModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("limen-model-\(UUID().uuidString)")
        let prefs = try #require(UserDefaults(suiteName: "limen-model-\(UUID().uuidString)"))
        return LimenModel(prefs: prefs, root: root)
    }

    private func finalized(_ id: String) -> HandoverProtocol {
        var p = HandoverProtocol(id: id, kind: .exit, createdEpochMs: 1)
        p.parties = [Party(.tenant, name: "Tenant"), Party(.landlord, name: "Owner")]
        p.finalizedEpochMs = 1
        p.evidenceFingerprint = "fixture-fingerprint"
        p.exportedEpochMs = 1
        return p
    }

    @Test func exportMergesAReceiptChangedBehindAnOperationBarrier() async throws {
        let model = try model()
        model.setActiveProtocol(finalized("one"))
        let gate = ExportBarrier()
        model.exportRenderer = { p, _, _ in await gate.render(p) }
        model.exportPdf()
        await gate.waitForStart()
        model.recordDelivery(participantId: "legacy-Tenant", method: .electronic, note: "Delivered during rendering")
        #expect(model.flush())
        await gate.finish()
        await model.exportTask?.value
        let saved = try #require(model.store.load("one"))
        #expect(saved.deliveryReceipts.first?.note == "Delivered during rendering")
        #expect(saved.deliveryRevision == 1)
        #expect(saved.exportHistory.first?.deliveryRevision == 0)
        #expect(model.working?.deliveryReceipts == saved.deliveryReceipts)
    }

    @Test func exportCannotStampADifferentOpenRecord() async throws {
        let model = try model()
        model.setActiveProtocol(finalized("one"))
        let gate = ExportBarrier()
        model.exportRenderer = { p, _, _ in await gate.render(p) }
        model.exportPdf()
        await gate.waitForStart()
        model.closeFlow()
        let other = HandoverProtocol(id: "two", kind: .entry, createdEpochMs: 2)
        model.setActiveProtocol(other)
        #expect(model.flush())
        await gate.finish()
        await model.exportTask?.value
        #expect(model.working?.id == "two")
        #expect(model.working?.exportedEpochMs == 0)
        #expect(model.store.load("one")?.exportHistory.count == 1)
        #expect(model.store.load("two")?.exportHistory.isEmpty == true)
    }

    @Test func firstSaveFailureRetainsDraftAndCanBeRetried() throws {
        let model = try model()
        let directory = model.store.root.appendingPathComponent("protocols")
        try FileManager.default.removeItem(at: directory)
        try Data("blocked".utf8).write(to: directory)
        model.createProtocol(.entry, sessionRole: .tenant, sessionName: "Q", sessionIdentity: SessionIdentity())
        let id = try #require(model.working?.id)
        #expect(model.saveError != nil)
        model.closeFlow()
        #expect(model.working?.id == id)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #expect(model.flush())
        #expect(model.saveError == nil)
        model.closeFlow()
        #expect(model.working == nil)
        #expect(model.store.load(id) != nil)
    }

    @Test func clearingReservationIsDurableAndRequiresNamedConsent() throws {
        let model = try model()
        var p = HandoverProtocol(id: "reservation", kind: .exit, createdEpochMs: 1)
        p.parties = [Party(.tenant, name: "Tenant"), Party(.landlord, name: "Landlord")]
        p.signatures = [Signature(.tenant, name: "Tenant", plane: .record, refused: true, reservation: "Old note")]
        model.setActiveProtocol(p)
        model.setRecordReservation(participantId: "legacy-Tenant", "")
        model.refuseSignature(.tenant, plane: .record)
        #expect(model.flush())
        let saved = try #require(model.store.load(p.id))
        #expect(saved.signatures.first?.reservation == "")
        #expect(saved.details.reservations["legacy-Tenant"] == "")
        let png = try #require(UIImage(systemName: "signature")?.pngData())
        model.keepSignature(.tenant, plane: .record, png: png)
        let before = model.working?.address
        model.edit { p in var next = p; next.address = "New address"; return next }
        #expect(model.working?.address == before)
        #expect(model.pendingEditNames == ["Tenant"])
        model.confirmMaterialEdit()
        #expect(model.working?.address == "New address")
        #expect(model.working?.isCurrent(try #require(model.working?.signatures.first)) == false)
    }

    @Test func undoDoesNotRollBackTheSaveSequence() throws {
        let model = try model()
        var p = HandoverProtocol(id: "undo", kind: .entry, createdEpochMs: 1)
        p.defects = [Defect(id: "d", text: "Finding")]
        model.setActiveProtocol(p)
        #expect(model.flush())
        model.removeDefect("d")
        let token = try #require(model.undoNotice?.token)
        #expect(model.persistWorking())
        let sequence = try #require(model.working?.saveSequence)
        model.undo(token)
        #expect(model.flush())
        #expect(model.working?.saveSequence == sequence + 1)
        #expect(model.store.load(p.id)?.defects.count == 1)
    }

    @Test func materialEditConsentPreservesAConcurrentFlushSequence() throws {
        let model = try model()
        var p = HandoverProtocol(id: "consent-save", kind: .entry, createdEpochMs: 1)
        p.parties = [Party(.tenant, name: "Tenant"), Party(.landlord, name: "Owner")]
        model.setActiveProtocol(p)
        let png = try #require(UIImage(systemName: "signature")?.pngData())
        model.keepSignature(.tenant, plane: .record, png: png)
        #expect(model.flush())
        model.edit { var next = $0; next.address = "Changed with consent"; return next }
        model.edit { var next = $0; next.place = "Another owned edit during consent"; return next }
        #expect(model.pendingEdit != nil)
        #expect(model.flush())
        let latest = try #require(model.working?.saveSequence)
        model.confirmMaterialEdit()
        #expect(model.flush())
        #expect(model.store.load(p.id)?.saveSequence == latest + 1)
        #expect(model.store.load(p.id)?.address == "Changed with consent")
        #expect(model.store.load(p.id)?.place == "Another owned edit during consent")
    }

    @Test func anOlderPreviewCannotApproveNewContent() async throws {
        let model = try model()
        model.setActiveProtocol(HandoverProtocol(id: "preview", kind: .entry, createdEpochMs: 1))
        let gate = ExportBarrier()
        model.previewRenderer = { record, _, _ in
            _ = await gate.render(record)
            // The renderer hands back two scratch files, as the real one does.
            let stem = FileManager.default.temporaryDirectory.appendingPathComponent("stale-preview-\(UUID().uuidString)")
            let pdf = stem.appendingPathExtension("pdf"), html = stem.appendingPathExtension("html")
            try Data("test renderer bytes".utf8).write(to: pdf)
            try Data("<p>Test preview</p>".utf8).write(to: html)
            return PdfExport.Document(pdf: pdf, html: html, pages: 1)
        }
        model.previewDocument()
        await gate.waitForStart()
        model.edit { p in var next = p; next.address = "Changed while rendering"; return next }
        await gate.finish()
        await model.previewTask?.value
        #expect(model.documentPreview == nil)
        model.confirmReview()
        #expect(model.working?.details.reviewRevision == -1)
    }

    @Test func seededExitCarriesAccessInventoryAndAgreedTimingWithoutOldEvidence() throws {
        let model = try model()
        var entry = finalized("entry-baseline")
        entry.kind = .entry
        entry.details.notificationClause = "Contract clause 12"
        entry.details.notificationDays = "10"
        entry.details.accessDevices = [AccessDevice(id: "fob", label: "Garage fob", identifier: "F-42", expected: 3, transferred: 2, note: "One was missing")]
        entry.details.actualTransferDate = "2026-01-01"
        entry.details.followUps = [FollowUp(id: "old", description: "Old issue")]
        var identity = SessionIdentity()
        identity.firstName = "Next"
        identity.lastName = "Operator"
        model.seedExitFrom(entry, sessionRole: .landlord, identity: identity)
        let exit = try #require(model.working)
        #expect(exit.seedId == entry.id)
        #expect(exit.details.accessDevices == [AccessDevice(id: "fob", label: "Garage fob", identifier: "F-42", expected: 2)])
        #expect(exit.details.notificationClause == "Contract clause 12")
        #expect(exit.details.notificationDays == "10")
        #expect(exit.details.actualTransferDate.isEmpty)
        #expect(exit.details.followUps.isEmpty)
        #expect(exit.signatures.isEmpty)
        #expect(exit.details.reviewRevision == -1)
    }
}
