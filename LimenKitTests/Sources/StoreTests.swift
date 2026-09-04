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

    @Test func unknownFieldsFromTheFutureAreSkipped() throws {
        let root = try temporaryRoot()
        let store = Store(root: root)
        try store.save(Self.fullProtocol())
        let file = root.appendingPathComponent("protocols/p1.json")
        let text = readText(file)
        // A version-2 writer adds a field this reader has never heard of.
        let brace = try #require(text.range(of: "{"))
        try writeText(text.replacingCharacters(in: brace, with: "{\n  \"fromTheFuture\": {\"x\": 1},"), to: file)
        #expect(store.load("p1") != nil)
    }

    @Test func corruptFileIsRefusedQuietlyAndDoesNotPoisonTheList() throws {
        let root = try temporaryRoot()
        let store = Store(root: root)
        try store.save(Self.fullProtocol())
        try writeText("{ not json", to: root.appendingPathComponent("protocols/broken.json"))
        #expect(store.list().count == 1)
        #expect(store.load("broken") == nil)
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
}
