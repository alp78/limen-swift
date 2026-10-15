import CoreGraphics
import Foundation
import UIKit
import PDFKit

/// The protocol as an A4 document, drawn with the platform's own PDF context: no library, no
/// fonts to embed by hand, black ink on white paper. The layout follows the paper canon it will
/// be compared against at a conciliation hearing: header, parties, the money and meter rubrics
/// this handover actually carries, the supplied objects, the findings numbered by room with the
/// explicit charge column, the record signatures, the deposit release instruction, and the
/// photo annex.
///
/// The paper prints what was recorded and nothing else. Undamaged surfaces do not appear,
/// because a page of "in order" lines beside three real findings buries the three; and a dossier
/// rubric nobody filled in does not appear either, because an empty field on a signed document
/// reads as an unanswered question. Records written before this, which do carry an exhaustive
/// item grid, still print theirs: those grades are part of what the parties put their names to.
///
/// The language of the document is the `Str` handed in, independent of the UI language: a
/// Lausanne regie hands a German-speaking tenant a French protocol or the reverse, and the choice
/// belongs to the moment of export.
///
/// Every measurement below is in the Android sheet's own units, a 1240 by 1754 page, and the
/// context is scaled so that sheet fills an A4 leaf: the same proportions to a tenth of a
/// percent, so nothing in the layout moved, and a print at 100 percent is the size it was meant to be.
public enum PdfExport {
    public enum ExportError: Error, Equatable {
        case notFinalized
        case integrityMismatch
        case rendering
    }

    static let pageWidth: CGFloat = 1240
    static let pageHeight: CGFloat = 1754
    static let margin: CGFloat = 90
    static let foot: CGFloat = 60
    static let a4 = CGSize(width: 595.276, height: 841.89)

    public static func export(_ p: HandoverProtocol, _ s: Str, photoDir: URL, signatureDir: URL, folder: URL = Exports.folder, now: Date = Date()) throws -> ExportedFile {
        guard p.isFinalized() else { throw ExportError.notFinalized }
        guard ProtocolIntegrity.matches(p, photoDir: photoDir, signatureDir: signatureDir) else { throw ExportError.integrityMismatch }
        let data = try render(p, s, photoDir: photoDir, signatureDir: signatureDir)
        let kind = p.kind == .entry ? s.entry : s.exit
        let name = "limen-\(kind.lowercased().replacingOccurrences(of: " ", with: "-"))-\(Exports.stamp(now)).pdf"
        return try Exports.write(name: name, in: folder) { url in try data.write(to: url) }
    }

    /// The document's bytes. Twice: the first pass only counts the sheets so the second can
    /// number them "3 / 7". A form that names its own total is a form nobody can quietly take a
    /// page out of, which is the tamper evidence paper has always used and people actually check.
    public static func render(_ p: HandoverProtocol, _ s: Str, photoDir: URL, signatureDir: URL) throws -> Data {
        try document(p, s, photoDir: photoDir, signatureDir: signatureDir).pdf
    }

    public struct Document: Sendable {
        public let pdf: Data
        public let html: Data
        public let pages: Int

        public init(pdf: Data, html: Data, pages: Int) {
            self.pdf = pdf
            self.html = html
            self.pages = pages
        }
    }

    public static func document(_ p: HandoverProtocol, _ s: Str, photoDir: URL, signatureDir: URL) throws -> Document {
        try EvidenceValidation.requireReadable(p, photoDir: photoDir, signatureDir: signatureDir)
        let reference = p.isFinalized() ? reference(p) : s.previewDraft
        let counted = try build(p, s, photoDir: photoDir, signatureDir: signatureDir, reference: reference, total: 0)
        let drawn = try build(p, s, photoDir: photoDir, signatureDir: signatureDir, reference: reference, total: counted.pages)
        guard drawn.pages == counted.pages, let pdf = PDFDocument(data: drawn.data),
              pdf.pageCount == drawn.pages, pdf.pageCount > 0, !(pdf.string ?? "").isEmpty else { throw ExportError.rendering }
        return Document(pdf: drawn.data, html: Data(drawn.html.utf8), pages: drawn.pages)
    }

    private static func build(_ p: HandoverProtocol, _ s: Str, photoDir: URL, signatureDir: URL, reference: String, total: Int) throws -> RenderPass {
        let sheet = try Sheet(s: s, reference: reference, total: total)
        let cards = p.dossierCards()
        title(sheet, p, s)
        header(sheet, p, s)
        integrity(sheet, p, s)
        legalOverlay(sheet, p, s)
        parties(sheet, p, s)
        dataController(sheet, p, s)
        if cards.contains(.contract) { contract(sheet, p, s) }
        if cards.contains(.deposit) { deposit(sheet, p, s) }
        if cards.contains(.meters) { meters(sheet, p, s) }
        if cards.contains(.keys) { keys(sheet, p, s) }
        rooms(sheet, p, s)
        objects(sheet, p, s)
        findings(sheet, p, s)
        if cards.contains(.notes) { remarks(sheet, p, s) }
        for section in RecordContent.extraContent(record: p, strings: s) {
            sheet.sectionTitle(section.title)
            for paragraph in section.paragraphs { sheet.wrapped(paragraph, sheet.body) }
        }
        signatures(sheet, p, s, signatureDir)
        delivery(sheet, p, s)
        release(sheet, p, s)
        annex(sheet, p, s, photoDir, measuring: total == 0)
        return try sheet.close()
    }

    /// The filing reference is a readable prefix of the frozen evidence fingerprint.
    static func reference(_ p: HandoverProtocol) -> String { "LIMEN-\(p.evidenceFingerprint.prefix(16))" }

    // MARK: Sections

    private static func title(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        sheet.newPage()
        // The badge, top right of the first page. A protocol that ends in a conciliation hearing
        // should look like it came from somewhere: the same seal as the launcher and the header,
        // drawn from the same resource so the three can never drift apart.
        let badge: CGFloat = 64
        if let url = Bundle.limenKit.url(forResource: "limen_mark", withExtension: "png"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let mark = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            sheet.image(mark, in: CGRect(x: pageWidth - margin - badge, y: sheet.y, width: badge, height: badge))
        }
        let kind = p.kind == .entry ? s.entry : s.exit
        sheet.text("\(s.protocolKind.uppercased()) · \(kind.uppercased())", margin, sheet.y + sheet.titleInk.size, sheet.titleInk)
        // The rule clears the badge as well as the text, whichever is taller.
        sheet.y = max(sheet.y + sheet.titleInk.size + 12, sheet.y + badge + 10)
        sheet.line(margin, sheet.y, pageWidth - margin, sheet.y, sheet.black, 3)
        sheet.gap(8)
    }

    private static func header(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        sheet.labeledRow([(s.address, p.address), (s.place, p.place)])
        if let canton = p.objectCanton {
            sheet.labeledRow([(s.cantonLabel, s.canton(canton)), (s.legalBasis, s.legalProfile(p.resolvedLegalOverlay()?.profile ?? p.legalProfile()))])
        }
        sheet.labeledRow([
            (s.objectDetail, p.objectDetail),
            (s.handoverDate, [SwissDate.display(p.handoverDate), p.handoverTime].filter { !$0.isBlank }.joined(separator: " ")),
        ])
        if !p.lastProtocolDate.isBlank {
            sheet.labeledRow([(s.lastProtocol, SwissDate.display(p.lastProtocolDate))])
        }
    }

    /// Identifies the immutable record and, when applicable, the record it corrects.
    private static func integrity(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        sheet.sectionTitle(p.isFinalized() ? s.pdfFinalized : s.previewDraft)
        if p.isFinalized() { sheet.wrapped("\(s.fingerprint): \(p.evidenceFingerprint)", sheet.small) }
        if !p.amendedFromId.isBlank {
            // By the reference the amended document actually prints on itself. The raw store id
            // appears on no PDF anywhere, so it identified nothing to a reader.
            let amended = p.amendedFromFingerprint.isBlank ? p.amendedFromId : "LIMEN-\(p.amendedFromFingerprint.prefix(16))"
            sheet.wrapped("\(s.pdfAmends): \(amended)", sheet.small)
        }
    }

    /// The dated canton checks actually recorded, never inferred into an older frozen PDF.
    private static func legalOverlay(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        if p.legalOverlay == LegalOverlayRecord() { return }
        guard let overlay = p.resolvedLegalOverlay() else { return }
        sheet.sectionTitle(s.legalOverlayTitle)
        sheet.wrapped("\(s.canton(overlay.canton)) · \(s.legalProfile(overlay.profile))", sheet.body)
        if p.kind == .entry {
            sheet.wrapped("\(s.initialRentForm): \(s.initialRentFormRule(overlay.initialRentFormRule))", sheet.small)
        }
        // Only the requirements this record still resolves. Printed from the raw answer map, a
        // deposit set back to None left "Deposit proof: Confirmed" on a record stating there is
        // no deposit, which neither the panel nor the completeness gate would ever have shown.
        for requirement in overlay.requirements.sorted(by: { $0.ordinal < $1.ordinal }) {
            guard let status = p.legalOverlay.status(requirement) else { continue }
            sheet.wrapped("\(s.legalRequirement(requirement)): \(s.legalCheckStatus(status))", sheet.body)
            if let note = p.legalOverlay.notes[requirement], !note.isBlank { sheet.wrapped(note, sheet.body) }
        }
        if !p.legalOverlay.note.isBlank {
            sheet.wrapped("\(s.legalOverlayNote): \(p.legalOverlay.note)", sheet.small)
        }
        let ruleSet = p.legalOverlay.ruleSetId.isBlank ? "" : " (\(p.legalOverlay.ruleSetId))"
        // Cited per canton: the BWO form is federal, the RULV are Vaud's, and naming them on a
        // Bern or Ticino record stated something untrue about its legal basis.
        sheet.wrapped("\(s.legalSnapshotFor(overlay.canton))\(ruleSet)", sheet.small)
    }

    private static func parties(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        sheet.sectionTitle(s.parties)
        for party in p.parties {
            var detail: [String] = []
            if !party.agency.isBlank { detail.append("\(s.companyName): \(party.agency)") }
            if !party.authority.isBlank { detail.append("\(s.authority): \(party.authority)") }
            if !party.representedBy.isBlank { detail.append("\(s.representedBy): \(party.representedBy)") }
            if !party.phone.isBlank { detail.append(party.phone) }
            if !party.email.isBlank { detail.append(party.email) }
            if !party.address.isBlank { detail.append("\(s.newAddress): \(party.address)") }
            sheet.labeledRow([(s.role(party.role), party.name)])
            let joined = detail.joined(separator: " · ")
            if !joined.isBlank {
                sheet.wrapped(joined, sheet.small, x: margin + 30, width: pageWidth - 2 * margin - 30)
            }
        }

        // Who compiled the record, with the contact the session was opened under. This was
        // collected and validated at the start of every session and then printed nowhere, which
        // made the whole identity form a set of fields that changed no document.
        let by = p.sessionIdentity
        var contact: [String] = []
        // An agency session names the firm first and the person present as its representative.
        if !by.company.isBlank {
            contact.append(by.company)
            if !by.fullName.isBlank { contact.append("\(s.representedBy): \(by.fullName)") }
        } else if !by.fullName.isBlank {
            contact.append(by.fullName)
        }
        if !by.phone.isBlank { contact.append(by.phone) }
        let lines = [by.addressLine, by.placeLine].filter { !$0.isBlank }
        if !lines.isEmpty { contact.append(lines.joined(separator: ", ")) }
        if !contact.isEmpty {
            sheet.gap(4)
            let side = p.sessionRole.map { " (\(s.role($0)))" } ?? ""
            sheet.wrapped("\(s.compiledBy)\(side): \(contact.joined(separator: " · "))", sheet.small)
        }
    }

    private static func dataController(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        let controller = p.controllerIdentity
        if controller.isBlank { return }
        sheet.sectionTitle(s.controllerTitle)
        if !controller.organisation.isBlank { sheet.wrapped(controller.organisation, sheet.value) }
        var contact: [String] = []
        if !controller.contactName.isBlank { contact.append(controller.contactName) }
        if !controller.email.isBlank { contact.append(controller.email) }
        if !controller.phone.isBlank { contact.append(controller.phone) }
        let place = [controller.postalCode, controller.city].filter { !$0.isBlank }.joined(separator: " ")
        let lines = [controller.street, place].filter { !$0.isBlank }
        if !lines.isEmpty { contact.append(lines.joined(separator: ", ")) }
        if !contact.isEmpty { sheet.wrapped(contact.joined(separator: " · "), sheet.body) }
    }

    private static func deposit(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        sheet.sectionTitle(s.deposit)
        sheet.wrapped(s.depositKind(p.deposit.kind), sheet.body)
        switch p.deposit.kind {
        case .insurance:
            sheet.labeledRow([(s.depositProvider, p.deposit.provider), (s.depositPolicy, p.deposit.policyNo), (s.depositAmount, p.deposit.amountChf)])
        case .bankAccount:
            sheet.labeledRow([(s.depositBankName, p.deposit.bank), (s.depositAccount, p.deposit.account), (s.depositAmount, p.deposit.amountChf)])
        case .none, .unknown:
            break
        }
    }

    private static func contract(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        sheet.sectionTitle(s.contract)
        sheet.labeledRow([
            (s.monthlyRent, p.contract.monthlyRentChf),
            (s.serviceCharges, p.contract.serviceChargesChf),
            (s.noticeDate, SwissDate.display(p.contract.noticeDate)),
        ])
        sheet.labeledRow([
            (s.leaseConcludedOn, SwissDate.display(p.contract.conclusionDate)),
            (s.tenancyStart, SwissDate.display(p.contract.startDate)),
            (s.tenancyEnd, SwissDate.display(p.contract.endDate)),
        ])
    }

    private static func meters(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        sheet.sectionTitle(s.meters)
        sheet.labeledRow([(s.meterElec1, p.meters.electricity1), (s.meterElec2, p.meters.electricity2), (s.meterGas, p.meters.gas)])
        sheet.labeledRow([(s.meterWater, p.meters.water), (s.meterHotWater, p.meters.hotWater), (s.meterOil, p.meters.heatingOil)])
    }

    private static func keys(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        sheet.sectionTitle(s.keysLabel)
        sheet.wrapped("\(s.keyTransferLabel): \(s.keyTransfer(p.keyTransfer))", sheet.body)
        if !p.keyTransferNote.isBlank { sheet.wrapped(p.keyTransferNote, sheet.small) }
        if p.keyTransfer == .noPhysicalKeys { return }
        let keyText = p.keys.filter { $0.count >= 1 }.map { k -> String in
            let label = k.kind == .other && !k.label.isBlank ? k.label : s.keyKind(k.kind)
            return "\(label): \(k.count)"
        }.joined(separator: "   ")
        sheet.wrapped(keyText.ifBlank("–"), sheet.value)
        // Older records counted a room's own door keys inside the room. Those still print,
        // once, here rather than twice as they used to.
        let roomKeys = p.rooms.filter { $0.keysCount > 0 }
        if !roomKeys.isEmpty {
            sheet.wrapped(roomKeys.map { r in "\(r.name.ifBlank(s.room(r.kind))): \(r.keysCount)" }.joined(separator: "   "), sheet.value)
        }
        if p.selfMadeKeys { sheet.wrapped(s.selfMadeKeys, sheet.body) }
    }

    /// Everything supplied with the flat, one line each, grouped the way it was entered.
    private static func objects(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        // Both, when a record carries both. Returning after the legacy block only while objects
        // was empty meant adding one row to a seeded exit dropped the whole inherited inventory.
        legacyExtras(sheet, p, s)
        if p.objects.isEmpty { return }
        sheet.sectionTitle(s.objects)
        var groups: [(ObjectGroup, String)] = []
        for entry in p.objects where !groups.contains(where: { $0.0 == entry.group && $0.1 == entry.groupLabel }) {
            groups.append((entry.group, entry.groupLabel))
        }
        for (group, groupLabel) in groups {
            let rows = p.objects.filter { $0.group == group && $0.groupLabel == groupLabel }
            sheet.ensure(50)
            sheet.wrapped(groupLabel.ifBlank(s.objectGroup(group)).uppercased(), sheet.label)
            for entry in rows {
                var detail: [String] = [entry.inspected ? s.objectInspected : s.notInspected]
                if let room = p.rooms.first(where: { $0.id == entry.roomId }) { detail.append(room.name.ifBlank(s.room(room.kind))) }
                if !entry.note.isBlank { detail.append(entry.note) }
                if !entry.photos.isEmpty { detail.append("\(s.photos): \(entry.photos.count)") }
                let joined = detail.joined(separator: " · ")
                sheet.wrapped(entry.displayName(s) + (joined.isBlank ? "" : "   \(joined)"), sheet.body, x: margin + 30, width: pageWidth - 2 * margin - 30)
            }
            sheet.gap(6)
        }
    }

    /// The set-of-toggles inventory older records carry, printed the way they were signed.
    private static func legacyExtras(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        let appliances = p.extras.appliances.sorted { $0.ordinal < $1.ordinal }.map(s.appliance) + p.extras.customAppliances
        let furniture = p.extras.furniture.sorted { $0.ordinal < $1.ordinal }.map(s.furniture) + p.extras.customFurniture
        if appliances.isEmpty, furniture.isEmpty { return }
        sheet.sectionTitle(s.objects)
        if !appliances.isEmpty { sheet.wrapped("\(s.appliances): \(appliances.joined(separator: " · "))", sheet.body) }
        if !furniture.isEmpty { sheet.wrapped("\(s.furnitureLabel): \(furniture.joined(separator: " · "))", sheet.body) }
    }

    /// The rooms the record covers, named once, so the reader knows the shape of the flat.
    private static func rooms(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        if p.rooms.isEmpty { return }
        sheet.sectionTitle(s.stepInspection)
        for room in p.rooms {
            let status = room.inspected ? s.roomInspected : s.notInspected
            sheet.wrapped("\(room.name.ifBlank(s.room(room.kind))) · \(status)", sheet.body)
        }
        for room in p.rooms where room.hasLegacyGrid {
            sheet.ensure(60)
            sheet.wrapped(room.name.ifBlank(s.room(room.kind)).uppercased(), sheet.label)
            legacyGrid(sheet, p, s, room)
        }
    }

    /// The findings, by room and then by object.
    ///
    /// Each is numbered by its position in the whole record rather than within its room, so the
    /// number under a photograph in the annex names exactly one finding on exactly one page.
    ///
    /// A room explicitly confirmed as inspected prints even when it has no finding. Legacy seeded
    /// rooms remain labelled not inspected, so the PDF never turns their silence into a claim
    /// that somebody checked them.
    private static func findings(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        sheet.sectionTitle("\(s.defects) (\(p.defects.count))")
        if p.defects.isEmpty { sheet.wrapped("–", sheet.body) }
        for room in p.rooms {
            let found = Report.roomFindings(p, room.id)
            if found.isEmpty, !room.inspected { continue }
            sheet.ensure(60)
            sheet.wrapped(room.name.ifBlank(s.room(room.kind)).uppercased(), sheet.label)
            if found.isEmpty {
                sheet.wrapped(s.inspectedNoDefects, sheet.body)
            } else {
                for item in found { finding(sheet, p, s, item.defect, item.number) }
            }
            sheet.gap(6)
        }

        let onObjects = Report.objectFindings(p)
        if !onObjects.isEmpty {
            sheet.ensure(60)
            sheet.wrapped(s.objects.uppercased(), sheet.label)
            for item in onObjects { finding(sheet, p, s, item.defect, item.number) }
        }

        // A finding whose room is gone would otherwise vanish from the paper while still counting
        // in the heading and carrying a caption in the annex.
        let orphaned = Report.orphanedFindings(p)
        if !orphaned.isEmpty {
            sheet.ensure(60)
            sheet.wrapped(s.defects.uppercased(), sheet.label)
            for item in orphaned { finding(sheet, p, s, item.defect, item.number) }
        }
    }

    /// One numbered finding: what it is about, what it says, and everything hanging on it.
    private static func finding(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str, _ d: Defect, _ number: Int) {
        sheet.ensure(80)
        sheet.text("\(number).", margin, sheet.y + sheet.value.size, sheet.value)
        var wherePieces: [String] = []
        if !d.objectId.isBlank, let entry = p.objects.first(where: { $0.id == d.objectId }) {
            wherePieces.append(entry.displayName(s))
        }
        if let item = p.defectItemLabel(d, s) { wherePieces.append(item) }
        let location = wherePieces.joined(separator: " · ")
        if !location.isBlank {
            sheet.text(sheet.ellipsize(location, sheet.small, pageWidth - 2 * margin - 60), margin + 60, sheet.y + sheet.small.size + 2, sheet.small)
            sheet.y += sheet.small.size + 8
        }
        sheet.wrapped(d.text.ifBlank("–"), sheet.body, x: margin + 60, width: pageWidth - 2 * margin - 60)
        var meta: [String] = []
        if d.chargedToTenant { meta.append(s.chargedToTenant.uppercased()) }
        switch d.fixBy {
        case .tenant: meta.append("\(s.fixByLabel): \(s.role(.tenant))")
        case .landlord: meta.append("\(s.fixByLabel): \(s.role(.landlord))")
        case .open: break
        }
        if !d.fixDeadline.isBlank { meta.append("\(s.fixDeadline) \(SwissDate.display(d.fixDeadline))") }
        if !d.costNote.isBlank { meta.append("\(s.costNote): \(d.costNote)") }
        if !d.photos.isEmpty { meta.append("\(s.photos): \(d.photos.count)") }
        if d.tenantResponse != .notStated { meta.append("\(s.tenantResponseLabel): \(s.tenantResponse(d.tenantResponse))") }
        if !meta.isEmpty {
            sheet.wrapped(meta.joined(separator: " · "), sheet.small, x: margin + 60, width: pageWidth - 2 * margin - 60)
        }
        if !d.reservation.isBlank {
            sheet.wrapped("\(s.reservationLabel): \(d.reservation)", sheet.small, x: margin + 60, width: pageWidth - 2 * margin - 60)
        }
        if !d.tenantComment.isBlank {
            sheet.wrapped("\(s.tenantComment): \(d.tenantComment)", sheet.small, x: margin + 60, width: pageWidth - 2 * margin - 60)
        }
        for (id, position) in d.participantPositions.entries {
            let name = p.parties.first { $0.participantKey() == id }?.signerName() ?? id
            sheet.wrapped("\(name) · \(s.tenantResponse(position.response)) · \(position.comment)", sheet.body)
        }
        sheet.gap(8)
    }

    /// The exhaustive item grid, printed only for a record that was signed with one.
    ///
    /// Two columns of item lines: the form look, at half the paper. The state is ellipsized into
    /// its own gutter, because "In Ordnung" in the right-hand column used to be drawn straight
    /// through the margin.
    private static func legacyGrid(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str, _ room: Room) {
        let colWidth = (pageWidth - 2 * margin - 40) / 2
        let stateWidth: CGFloat = 140
        let lines: [(String, String)] = room.items.map { item in
            let name = item.key == .custom && !item.label.isBlank ? item.label : s.item(item.key)
            let defectNos = p.defects.enumerated()
                .filter { pair in
                    pair.element.roomId == room.id && pair.element.item == item.key &&
                        (pair.element.itemId.isBlank || item.itemId.isBlank || pair.element.itemId == item.itemId)
                }
                .map { $0.offset + 1 }
            let state: String
            if !defectNos.isEmpty {
                state = "! " + defectNos.map(String.init).joined(separator: ",")
            } else if item.grade == .notChecked {
                state = ""
            } else if p.style == .binary {
                state = s.grade(.ok)
            } else {
                state = s.gradeShort(item.grade)
            }
            return (name, state)
        }
        let rowsPerCol = (lines.count + 1) / 2
        var i = 0
        while i < rowsPerCol {
            sheet.ensure(30)
            for col in 0..<2 {
                let index = i + col * rowsPerCol
                if index < lines.count {
                    let (name, state) = lines[index]
                    let x = margin + CGFloat(col) * (colWidth + 40)
                    sheet.text(sheet.ellipsize(name, sheet.body, colWidth - stateWidth - 20), x, sheet.y + sheet.body.size, sheet.body)
                    sheet.text(sheet.ellipsize(state, sheet.value, stateWidth), x + colWidth - stateWidth, sheet.y + sheet.body.size, sheet.value)
                }
            }
            sheet.y += sheet.body.size + 8
            i += 1
        }
    }

    /// The Notes component: free remarks and the service-charge date, when it is on the record.
    private static func remarks(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        if p.remarks.isBlank, p.chargesStatementBy.isBlank { return }
        // Hoisted above both branches: opened only inside the remarks branch, a service-charge
        // date with no remarks printed under the DEFECTS heading, reading as the last finding.
        sheet.sectionTitle(s.remarks)
        if !p.remarks.isBlank { sheet.wrapped(p.remarks, sheet.body) }
        if !p.chargesStatementBy.isBlank {
            if !p.remarks.isBlank { sheet.gap(8) }
            sheet.wrapped("\(s.chargesBy) \(SwissDate.display(p.chargesStatementBy))", sheet.body)
        }
    }

    private static func signatures(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str, _ signatureDir: URL) {
        // The record signature is always printed, with its meaning above the ink.
        sheet.sectionTitle(s.signRecordTitle)
        // A handover one party did not attend is a statement about these signatures, so it is
        // printed here and unconditionally. It used to live under the remarks section, which
        // meant it vanished from the paper whenever that optional component was not added.
        if p.oneSided {
            sheet.wrapped(s.oneSided.uppercased(), sheet.section)
            if let reason = p.unilateralReason {
                sheet.wrapped("\(s.unilateralReasonLabel): \(s.unilateralReason(reason))", sheet.body)
            }
            if !p.unilateralNote.isBlank { sheet.wrapped(p.unilateralNote, sheet.small) }
            sheet.wrapped(s.infoOneSided, sheet.small)
            sheet.gap(8)
        }
        sheet.wrapped(s.signRecordMeaning, sheet.small)
        sheet.gap(10)
        drawPlane(sheet, p, s, signatureDir, .record)
        if p.signatures.contains(where: { $0.plane == .costs }) {
            sheet.sectionTitle(s.costNote)
            drawPlane(sheet, p, s, signatureDir, .costs)
        }
        sheet.wrapped(s.inkEvidenceNotice, sheet.small)

        // The Swiss ritual, said on the document itself: two identical papers, one per party. In
        // Vaud the RULV require exactly that, and a tenant who reads it here knows to leave the
        // flat holding one.
        sheet.gap(6)
        sheet.wrapped(s.pdfTwoCopies, sheet.small)
    }

    private static func drawPlane(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str, _ dir: URL, _ plane: Plane) {
        let sigs = p.signatures.filter { $0.plane == plane && (p.isCurrent($0) || plane == .costs) }
        if plane == .record {
            for party in CompletionRules.requiredRecordParticipants(p) {
                guard !sigs.contains(where: { $0.participantId.isBlank ? party.id.isBlank && $0.role == party.role : $0.participantId == party.participantKey() }) else { continue }
                sheet.wrapped("\(s.role(party.role)) · \(party.signerName()) · \(s.notSigned)", sheet.body)
                let reservation = p.reservationFor(party: party)
                if !reservation.isBlank { sheet.wrapped("\(s.reservationLabel): \(reservation)", sheet.small) }
                sheet.gap(14)
            }
        }
        if sigs.isEmpty {
            sheet.wrapped(s.notSigned, sheet.body)
            return
        }
        for sig in sigs {
            sheet.ensure(190)
            let x = margin
            if sig.refused || !sig.outcome.isBlank {
                let outcome = sig.outcome == "absent" ? s.absentOutcome : sig.outcome == "unable" ? s.unableToDraw : s.refusedNote
                sheet.wrapped(outcome, sheet.body)
                sheet.y += sheet.value.size + 6
            } else if !sig.file.isBlank, let image = PhotoDecode.sampled(dir.appendingPathComponent(sig.file), targetWidth: 840) {
                let maxW: CGFloat = 420
                let maxH: CGFloat = 130
                let scale = min(maxW / CGFloat(image.width), maxH / CGFloat(image.height), 1)
                let w = CGFloat(image.width) * scale
                let h = CGFloat(image.height) * scale
                sheet.image(image, in: CGRect(x: x, y: sheet.y, width: w, height: h), alt: sig.name)
                sheet.y += h + 4
            } else if !sig.file.isBlank { sheet.renderingFailed = true }
            sheet.line(x, sheet.y + 4, x + 420, sheet.y + 4, sheet.ruleColour, 1.5)
            sheet.y += 10
            var caption: [String] = [s.role(sig.role)]
            if !sig.name.isBlank { caption.append(sig.name) }
            if !sig.reservation.isBlank { caption.append("\(s.reservationLabel): \(sig.reservation)") }
            if sig.epochMs > 0 { caption.append("\(s.capturedOn): \(formatMoment(sig.epochMs))") }
            caption.append("\(s.revisionLabel): \(sig.contentRevision)")
            sheet.wrapped(caption.joined(separator: " · "), sheet.small)
            sheet.gap(14)
        }
    }

    static func formatMoment(_ epochMs: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm z"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000))
    }

    private static func delivery(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        if p.deliveryReceipts.isEmpty { return }
        sheet.sectionTitle(s.copyDelivery)
        sheet.wrapped(s.deliverySelfDeclared, sheet.small)
        let roleOrder = Role.allCases
        for receipt in p.deliveryReceipts.sorted(by: { (roleOrder.firstIndex(of: $0.role) ?? 0) < (roleOrder.firstIndex(of: $1.role) ?? 0) }) {
            var detail: [String] = [p.parties.first { $0.participantKey() == receipt.participantId }?.signerName() ?? s.role(receipt.role), s.deliveryMethod(receipt.method)]
            if receipt.epochMs > 0 { detail.append(formatMoment(receipt.epochMs)) }
            if !receipt.note.isBlank { detail.append(receipt.note) }
            sheet.wrapped(detail.joined(separator: " · "), sheet.body)
        }
    }

    private static func release(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        guard p.kind == .exit, p.deposit.kind == .bankAccount || p.deposit.kind == .insurance else { return }
        let releaseText: String
        switch p.deposit.kind {
        case .bankAccount: releaseText = s.releaseBank
        case .insurance: releaseText = s.releaseInsurance
        case .none, .unknown: releaseText = ""
        }
        var need: CGFloat = 70 + CGFloat(sheet.wrapLines(releaseText, sheet.body, pageWidth - 2 * margin).count) * (sheet.body.size + 7)
        let providerLine = "\(s.depositProvider): \(p.deposit.provider)" + (p.deposit.policyNo.isBlank ? "" : " · \(s.depositPolicy): \(p.deposit.policyNo)")
        if p.deposit.kind == .insurance, !p.deposit.provider.isBlank {
            need += 12 + CGFloat(sheet.wrapLines(providerLine, sheet.value, pageWidth - 2 * margin).count) * (sheet.value.size + 7)
        }
        sheet.ensure(need)
        sheet.sectionTitle(s.releaseTitle)
        switch p.deposit.kind {
        case .bankAccount:
            sheet.wrapped(releaseText, sheet.body)
        case .insurance:
            sheet.wrapped(releaseText, sheet.body)
            if !p.deposit.provider.isBlank {
                sheet.gap(6)
                sheet.wrapped(providerLine, sheet.value)
            }
        case .none, .unknown:
            break
        }
    }

    /// A plate's caption. A finding is cited by the number it prints under, which is what makes
    /// the annex checkable against the body; an object is cited by name, because an object has
    /// no number to cite.
    private static func caption(_ plate: Report.Plate, _ s: Str) -> String {
        switch plate.owner {
        case .finding(let number): return "\(s.defects) \(number)"
        case .supplied(let entry): return entry.displayName(s)
        }
    }

    private static func annex(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str, _ photoDir: URL, measuring: Bool) {
        var plates = Report.plates(p).map { ($0.file, caption($0, s), $0.sha256) }
        for (roomId, photos) in p.details.roomPhotos.entries {
            let room = p.rooms.first { $0.id == roomId }
            let label = room.map { $0.name.ifBlank(s.room($0.kind)) } ?? roomId
            plates += photos.map { ($0.file, label, $0.sha256) }
        }
        for meter in p.details.readings { plates += meter.photos.map { ($0.file, meter.label, $0.sha256) } }
        if plates.isEmpty { return }
        sheet.sectionTitle(s.pdfDefectAnnex)
        let width = pageWidth - 2 * margin
        for (file, caption, hash) in plates {
            sheet.ensure(650)
            if !measuring {
                guard let image = PhotoDecode.sampled(photoDir.appendingPathComponent(file), targetWidth: Int(width)) else {
                    sheet.renderingFailed = true
                    continue
                }
                let scale = min(width / CGFloat(image.width), 530 / CGFloat(image.height))
                sheet.image(image, in: CGRect(x: margin, y: sheet.y, width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale), alt: caption + " · " + file)
            }
            sheet.y += 540
            sheet.wrapped(caption + " · " + file, sheet.body)
            if !hash.isBlank { sheet.wrapped("SHA-256: " + hash, sheet.small) }
            sheet.gap(12)
        }
    }

}

extension HandoverProtocol {
    /// The item a finding names, or nil when it is about the room or the object as a whole.
    ///
    /// A finding written by this version carries its own label. Older records kept it on the
    /// room's item row instead, so those are still resolved through the row.
    public func defectItemLabel(_ d: Defect, _ s: Str) -> String? {
        guard let key = d.item else { return nil }
        if key == .custom {
            if !d.itemLabel.isBlank { return d.itemLabel }
            let legacy = rooms.first { $0.id == d.roomId }?.items.first {
                $0.key == key && (d.itemId.isBlank || $0.itemId.isBlank || d.itemId == $0.itemId)
            }
            if let label = legacy?.label, !label.isBlank { return label }
            return s.item(key)
        }
        return s.item(key)
    }

    /// Where a finding hangs: a room of the flat, or a supplied object.
    public func defectPlace(_ d: Defect, _ s: Str) -> String {
        if !d.objectId.isBlank {
            return objects.first { $0.id == d.objectId }?.displayName(s) ?? s.objects
        }
        guard let room = rooms.first(where: { $0.id == d.roomId }) else { return "" }
        return room.name.ifBlank(s.room(room.kind))
    }
}

extension ObjectEntry {
    /// What an object row is called: its catalogue entry when it has one, else what was typed.
    public func displayName(_ s: Str) -> String {
        switch group {
        case .appliance: return Appliance(rawValue: catalogue).map(s.appliance) ?? label
        case .furniture: return Furniture(rawValue: catalogue).map(s.furniture) ?? label
        case .other: return label
        }
    }
}
