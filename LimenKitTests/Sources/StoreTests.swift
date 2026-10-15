import Foundation
import Testing
@testable import LimenKit

@Suite struct StoreTests {
    static func fullProtocol(_ id: String = "p1") -> HandoverProtocol {
        var p = HandoverProtocol(id: id, kind: .exit, createdEpochMs: 1_000_000)
        p.style = .grades
        p.address = "Rue du Simplon 12"
        p.place = "1006 Lausanne"
        p.objectDetail = "3e étage gauche"
        p.handoverDate = "2026-09-30"
        p.handoverTime = "10:00"
        p.parties = [
            Party(.tenant, name: "A. Locataire", address: "Nouvelle adresse 1, 1200 Genève"),
            Party(.landlord, name: "Régie Exemple SA", representedBy: "B. Gérant"),
            Party(.witness, name: "C. Témoin"),
        ]
        p.deposit.kind = .insurance
        p.deposit.amountChf = "4500"
        p.deposit.provider = "SwissCaution"
        p.deposit.policyNo = "SC-123456"
        p.meters.electricity1 = "48214.7"
        p.meters.water = "1210.3"
        p.keys = [KeyCount(.apartment, count: 3), KeyCount(.mailbox, count: 1), KeyCount(.other, label: "Buanderie", count: 1)]
        p.selfMadeKeys = true
        var kitchen = Room(id: "r1", kind: .kitchen, items: Templates.itemsFor(.kitchen).map { RoomItem($0, grade: .ok) }, keysCount: 1)
        kitchen.freshPaintedWalls = true
        p.rooms = [kitchen, Room(id: "r2", kind: .room, name: "Chambre 2")]
        p.objects = [
            ObjectEntry(id: "o1", group: .appliance, catalogue: Appliance.fridge.rawValue, roomId: "r1", note: "Bosch, no de série 4471", photos: ["o1-1.jpg"], photoEvidence: [PhotoEvidence("o1-1.jpg", sha256: "AB", source: .camera)]),
            ObjectEntry(id: "o2", group: .other, groupLabel: "Jardin", label: "Tondeuse"),
        ]
        p.contract.monthlyRentChf = "1890"
        p.contract.serviceChargesChf = "220"
        p.contract.startDate = "2019-04-01"
        p.contract.endDate = "2026-09-30"
        p.contract.noticeDate = "2026-06-28"
        p.dossier = [.contract, .deposit, .meters, .keys]
        p.defects = [
            Defect(id: "d1", roomId: "r1", item: .worktop, text: "Brûlure ronde d'env. 2 cm près de la cuisinière", photos: ["d1-1.jpg", "d1-2.jpg"], chargedToTenant: true, fixBy: .landlord, costNote: "Sous réserve d'un devis"),
            Defect(id: "d2", item: .custom, text: "Joint fendu sur 4 cm", itemLabel: "Joint de porte", objectId: "o1"),
        ]
        p.remarks = "Signature du locataire: ne vaut pas reconnaissance de dette."
        p.chargesStatementBy = "2027-03-31"
        p.signatures = [
            Signature(.tenant, name: "A. Locataire", plane: .record, file: "tenant-record.png", epochMs: 5),
            Signature(.landlord, name: "B. Gérant", plane: .record, file: "landlord-record.png", epochMs: 6),
            Signature(.tenant, name: "A. Locataire", plane: .costs, refused: true, reservation: "Conteste le montant"),
        ]
        return p
    }

    @Test func roundTripKeepsEverything() throws {
        let store = Store(root: try temporaryRoot())
        let p = Self.fullProtocol()
        try store.save(p)
        #expect(store.load("p1") == p)
    }

    @Test func listSortsNewestFirst() throws {
        let store = Store(root: try temporaryRoot())
        var old = Self.fullProtocol("old")
        old.createdEpochMs = 1
        var new = Self.fullProtocol("new")
        new.createdEpochMs = 2
        try store.save(old)
        try store.save(new)
        #expect(store.list().map(\.id) == ["new", "old"])
    }

    @Test func unsupportedFieldsAreReportedWithoutRewritingTheOriginal() throws {
        let root = try temporaryRoot()
        let store = Store(root: root)
        try store.save(Self.fullProtocol())
        let file = root.appendingPathComponent("protocols/p1.json")
        let text = readText(file)
        // A version-2 writer adds a field this reader has never heard of.
        let brace = try #require(text.range(of: "{"))
        try writeText(text.replacingCharacters(in: brace, with: "{\n  \"fromTheFuture\": {\"x\": 1},"), to: file)
        #expect(store.load("p1") == nil)
        #expect(store.catalogue().unreadable == [Store.UnreadableRecord(id: "p1", hasRecovery: false)])
        #expect(throws: Store.SaveError.unreadablePrevious) { try store.save(Self.fullProtocol()) }
        #expect(readText(file).contains("fromTheFuture"))
    }

    @Test func corruptFileRemainsVisibleInTheCatalogue() throws {
        let root = try temporaryRoot()
        let store = Store(root: root)
        try store.save(Self.fullProtocol())
        try writeText("{ not json", to: root.appendingPathComponent("protocols/broken.json"))
        #expect(store.list().count == 1)
        #expect(store.load("broken") == nil)
        #expect(store.catalogue().unreadable.map(\.id) == ["broken"])
    }

    @Test func deleteTakesPhotosAndInkWithIt() throws {
        let root = try temporaryRoot()
        let store = Store(root: root)
        try store.save(Self.fullProtocol())
        try writeText("x", to: store.photoDir("p1").appendingPathComponent("d1-1.jpg"))
        try writeText("x", to: store.signatureDir("p1").appendingPathComponent("tenant-record.png"))
        store.delete("p1")
        #expect(store.load("p1") == nil)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: store.photoDir("p1").path)) ?? []).isEmpty)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: store.signatureDir("p1").path)) ?? []).isEmpty)
    }

    @Test func signedMeansRecordPlaneAndRefusalDoesNotCount() {
        let p = Self.fullProtocol()
        #expect(p.isSigned())
        var refusedOnly = p
        refusedOnly.signatures = [Signature(.tenant, plane: .record, refused: true)]
        #expect(!refusedOnly.isSigned())
    }

    @Test func theStoreOmitsDefaultsAndKeepsTheRequiredFields() {
        let text = Store.fileText(HandoverProtocol(id: "p9", kind: .entry, createdEpochMs: 7))
        #expect(text == "{\"id\":\"p9\",\"kind\":\"Entry\",\"createdEpochMs\":7}")
    }

    @Test func theMapsKeepTheirRecordedOrderThroughTheFile() throws {
        var p = HandoverProtocol(id: "m", kind: .entry, createdEpochMs: 1)
        p.legalOverlay = LegalOverlayRecord()
            .withStatus(.vaudExitReadiness, .confirmed)
            .withStatus(.leaseAndLocalTiming, .notApplicable)
        p.pendingRecordReservations = OrderedMap([(.landlord, "b"), (.tenant, "a")])
        let data = Data(Store.fileText(p).utf8)
        let back = try ProtocolJSON.decode(data)
        #expect(back.legalOverlay.checks.keys == [.vaudExitReadiness, .leaseAndLocalTiming])
        #expect(back.pendingRecordReservations.keys == [.landlord, .tenant])
        #expect(ProtocolJSON.encode(back, encodeDefaults: true).compact == ProtocolJSON.encode(p, encodeDefaults: true).compact)
    }

    @Test func kotlinEscapesAreWrittenAndReadBack() throws {
        var p = HandoverProtocol(id: "e", kind: .entry, createdEpochMs: 1)
        p.remarks = "line one\nline \"two\" \\ tab\t bell\u{07} é"
        let text = Store.fileText(p)
        #expect(text.contains("\"remarks\":\"line one\\nline \\\"two\\\" \\\\ tab\\t bell\\u0007 é\""))
        #expect(try ProtocolJSON.decode(Data(text.utf8)) == p)
    }

    @Test func staleAndDivergentWritesCannotReplaceARevision() throws {
        let store = Store(root: try temporaryRoot())
        var p = Self.fullProtocol()
        p.saveSequence = 1; p.contentRevision = 1
        try store.save(p)
        var latest = p
        latest.saveSequence = 2; latest.contentRevision = 2; latest.address = "Latest"
        try store.save(latest)
        #expect(throws: Store.SaveError.staleWrite) { try store.save(p) }
        var divergent = latest; divergent.address = "Same sequence, different facts"
        #expect(throws: Store.SaveError.staleWrite) { try store.save(divergent) }
        var olderFacts = latest; olderFacts.saveSequence = 3; olderFacts.contentRevision = 1
        #expect(throws: Store.SaveError.staleWrite) { try store.save(olderFacts) }
        #expect(store.load(p.id) == latest)
    }

    @Test func lastGoodRecoveryPreservesTheCorruptOriginal() throws {
        let root = try temporaryRoot(); let store = Store(root: root)
        var p = Self.fullProtocol(); p.saveSequence = 1
        try store.save(p)
        var latest = p; latest.saveSequence = 2; latest.address = "Latest"
        try store.save(latest)
        try writeText("damaged original", to: root.appendingPathComponent("protocols/p1.json"))
        #expect(store.catalogue().unreadable == [Store.UnreadableRecord(id: "p1", hasRecovery: true)])
        #expect(try store.recover("p1"))
        #expect(store.load("p1") == p)
        let retained = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("recovery/p1"), includingPropertiesForKeys: nil)
        #expect(retained.contains { $0.pathExtension == "quarantine" && readText($0) == "damaged original" })
    }

    @Test func filenameIdentityAndTraversalAreRejected() throws {
        let root = try temporaryRoot(); let store = Store(root: root)
        try store.save(Self.fullProtocol())
        try writeText(Store.fileText(Self.fullProtocol("different")), to: root.appendingPathComponent("protocols/wrong.json"))
        #expect(store.load("wrong") == nil)
        #expect(store.catalogue().unreadable.map(\.id) == ["wrong"])
        #expect(store.load("../protocols/p1") == nil)
        #expect(throws: Store.SaveError.unsafeIdentifier) { try store.save(Self.fullProtocol("../escape")) }
    }

    @Test func firstSaveFailureCanBeRetriedWithoutLosingTheValue() throws {
        let root = try temporaryRoot()
        try writeText("blocks directory", to: root.appendingPathComponent("protocols"))
        let store = Store(root: root); let p = Self.fullProtocol()
        #expect(throws: (any Error).self) { try store.save(p) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("protocols"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("protocols"), withIntermediateDirectories: true)
        try store.save(p)
        #expect(store.load(p.id) == p)
    }
    @Test func higherSequencesCannotChangeFinalizedFactsButCanRecordDistribution() throws {
        let store = Store(root: try temporaryRoot())
        var p = HandoverProtocol(id: "final", kind: .entry, createdEpochMs: 1)
        p.finalizedEpochMs = 1; p.evidenceFingerprint = "frozen"; p.saveSequence = 1
        try store.save(p)
        var changed = p; changed.saveSequence = 2; changed.address = "Different"
        #expect(throws: Store.SaveError.staleWrite) { try store.save(changed) }
        changed = p; changed.saveSequence = 2; changed.deliveryRevision = 1
        changed.deliveryReceipts = [DeliveryReceipt(.tenant, epochMs: 2)]
        try store.save(changed)
        #expect(store.load(p.id) == changed)
    }

}
