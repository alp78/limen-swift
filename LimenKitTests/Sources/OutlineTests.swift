import Foundation
import Testing
@testable import LimenKit

/// The sections a record prints, planned before anything is drawn and checked against what was
/// drawn: the paper canon's order, with the rooms and the annex sections beneath their headings.
@Suite struct OutlineTests {
    private let s = Str(.fr)

    private func evidence(_ file: String) -> PhotoEvidence {
        PhotoEvidence(file, sha256: "AB", capturedEpochMs: 1_761_030_000_000, source: .camera)
    }

    /// Every kind of section at once: dossier cards, rooms, objects, strays, extras, a costs plane, receipts, a deposit to release.
    private var full: HandoverProtocol {
        var p = HandoverProtocol(id: "outline", kind: .exit, createdEpochMs: 1)
        p.address = "Rue du Lac 3"
        p.place = "1000 Lausanne"
        p.objectCanton = .vd
        p.controllerIdentity.organisation = "Régie Test"
        p.dossier = [.contract, .deposit, .meters, .keys, .notes]
        p.dossierChosen = true
        p.deposit.kind = .bankAccount
        p.deposit.amountChf = "3000"
        p.meters.electricity1 = "12345"
        p.keys = [KeyCount(.apartment, count: 2)]
        p.rooms = [Room(id: "kitchen", kind: .kitchen, inspected: true), Room(id: "bath", kind: .bathroom, name: "Salle d’eau")]
        p.defects = [
            Defect(id: "d1", roomId: "bath", item: .walls, text: "Joint noirci", photos: ["d1-a.jpg"], photoEvidence: [evidence("d1-a.jpg")]),
            Defect(id: "d2", text: "Panier cassé", objectId: "dishwasher"),
            Defect(id: "d3", roomId: "gone", text: "Pièce supprimée"),
            Defect(id: "d4", text: "Objet disparu", objectId: "vanished"),
        ]
        p.objects = [ObjectEntry(id: "dishwasher", group: .appliance, catalogue: "Dishwasher", roomId: "kitchen")]
        p.remarks = "Remarque"
        p.signatures = [Signature(.tenant, name: "T", plane: .costs, contentRevision: 0)]
        p.deliveryReceipts = [DeliveryReceipt(.tenant, method: .inPerson)]
        p.details.understoodLanguage = "Français"
        p.details.roomPhotos["kitchen"] = [evidence("k.jpg")]
        return p
    }

    @Test func thePlanFollowsThePaperCanonWithRoomsAndAnnexSectionsBeneathTheirHeadings() {
        let expected: [Outline.Entry] = [
            Outline.Entry(s.controllerTitle), Outline.Entry(s.contract), Outline.Entry(s.deposit), Outline.Entry(s.meters), Outline.Entry(s.keysLabel),
            Outline.Entry(s.stepInspection), Outline.Entry("Cuisine", 1), Outline.Entry("Salle d’eau", 1),
            Outline.Entry(s.objects), Outline.Entry(s.defects),
            Outline.Entry(s.understoodLanguage),
            Outline.Entry(s.remarks), Outline.Entry(s.signRecordTitle), Outline.Entry(s.costSignatureTitle), Outline.Entry(s.copyDelivery), Outline.Entry(s.releaseTitle),
            Outline.Entry(s.pdfDefectAnnex), Outline.Entry("Cuisine", 1), Outline.Entry("Salle d’eau", 1),
        ]
        #expect(Outline.plan(full, s) == expected)
    }

    @Test func aBareRecordPlansOnlyTheSignatures() {
        let bare = HandoverProtocol(id: "bare", kind: .entry, createdEpochMs: 1)
        #expect(Outline.plan(bare, s) == [Outline.Entry(s.signRecordTitle)])
    }

    @Test func strayFindingsAreThoseWithoutARoomOrAListedObjectInRecordOrder() {
        #expect(Outline.strays(full).map(\.number) == [3, 4])
    }

    @Test func aRoomWithoutANameIsPlannedUnderItsKind() {
        #expect(Outline.roomName(Room(id: "k", kind: .kitchen), s) == "Cuisine")
        #expect(Outline.roomName(Room(id: "k", kind: .kitchen, name: "Atelier"), s) == "Atelier")
    }
}
