import Foundation

/// The sections a record prints, in order, decided before anything is drawn. The cover's contents
/// is printed from this list in both passes; the drawing pass marks each section as it opens, and
/// the export checks that the marks are this list. No graphics in it, so the order, which is the
/// paper canon's, is tested on its own.
enum Outline {
    struct Entry: Equatable {
        let title: String
        let level: Int

        init(_ title: String, _ level: Int = 0) {
            self.title = title
            self.level = level
        }
    }

    static func plan(_ p: HandoverProtocol, _ s: Str) -> [Entry] {
        let cards = p.dossierCards()
        var out: [Entry] = []
        if legalOverlay(p) { out.append(Entry(s.legalOverlayTitle)) }
        if controller(p) { out.append(Entry(s.controllerTitle)) }
        if cards.contains(.contract) { out.append(Entry(s.contract)) }
        if cards.contains(.deposit) { out.append(Entry(s.deposit)) }
        if meters(p) { out.append(Entry(s.meters)) }
        if cards.contains(.keys) { out.append(Entry(s.keysLabel)) }
        if !p.rooms.isEmpty {
            out.append(Entry(s.stepInspection))
            for room in p.rooms { out.append(Entry(roomName(room, s), 1)) }
        }
        if objects(p) { out.append(Entry(s.objects)) }
        if !strays(p).isEmpty { out.append(Entry(s.defects)) }
        for section in RecordContent.extraContent(record: p, strings: s) { out.append(Entry(section.title)) }
        if remarks(p) { out.append(Entry(s.remarks)) }
        out.append(Entry(s.signRecordTitle))
        if p.signatures.contains(where: { $0.plane == .costs }) { out.append(Entry(s.costSignatureTitle)) }
        if !p.deliveryReceipts.isEmpty { out.append(Entry(s.copyDelivery)) }
        if release(p) { out.append(Entry(s.releaseTitle)) }
        if !Report.plates(p).isEmpty {
            out.append(Entry(s.pdfDefectAnnex))
            for section in AnnexContent.sections(p, s) { out.append(Entry(section.title, 1)) }
        }
        return out
    }

    static func roomName(_ room: Room, _ s: Str) -> String { room.name.ifBlank(s.room(room.kind)) }

    /// Only the dated canton checks actually recorded, never inferred into a frozen record.
    static func legalOverlay(_ p: HandoverProtocol) -> Bool { p.legalOverlay != LegalOverlayRecord() && p.resolvedLegalOverlay() != nil }

    static func controller(_ p: HandoverProtocol) -> Bool { !p.controllerIdentity.isBlank }

    static func meters(_ p: HandoverProtocol) -> Bool { p.dossierCards().contains(.meters) && !p.meters.isBlank }

    /// The older toggle inventory, the object rows, or both.
    static func objects(_ p: HandoverProtocol) -> Bool { legacyObjects(p) || !p.objects.isEmpty }

    static func legacyObjects(_ p: HandoverProtocol) -> Bool {
        !p.extras.appliances.isEmpty || !p.extras.customAppliances.isEmpty || !p.extras.furniture.isEmpty || !p.extras.customFurniture.isEmpty
    }

    /// Findings with no panel to sit in: a finding whose room is gone, or one on an object the
    /// record no longer lists, in the record's own numbering.
    static func strays(_ p: HandoverProtocol) -> [Report.Numbered] {
        (Report.orphanedFindings(p) + Report.objectFindings(p).filter { f in !p.objects.contains { $0.id == f.defect.objectId } })
            .sorted { $0.number < $1.number }
    }

    static func remarks(_ p: HandoverProtocol) -> Bool {
        p.dossierCards().contains(.notes) && (!p.remarks.isBlank || !p.chargesStatementBy.isBlank)
    }

    static func release(_ p: HandoverProtocol) -> Bool { p.kind == .exit && p.deposit.kind != .none }
}
