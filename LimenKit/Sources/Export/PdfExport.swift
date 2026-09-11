import CoreGraphics
import Foundation
import UIKit

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
        let reference = reference(p)
        let counted = build(p, s, photoDir: photoDir, signatureDir: signatureDir, reference: reference, total: 0)
        return build(p, s, photoDir: photoDir, signatureDir: signatureDir, reference: reference, total: counted.pages).data
    }

    private static func build(_ p: HandoverProtocol, _ s: Str, photoDir: URL, signatureDir: URL, reference: String, total: Int) -> (data: Data, pages: Int) {
        let sheet = Sheet(s: s, reference: reference, total: total)
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
        signatures(sheet, p, s, signatureDir)
        delivery(sheet, p, s)
        release(sheet, p, s)
        annex(sheet, p, s, photoDir, measuring: total == 0)
        return sheet.close()
    }

    /// The filing reference is a readable prefix of the frozen evidence fingerprint.
    static func reference(_ p: HandoverProtocol) -> String { "LIMEN-\(p.evidenceFingerprint.prefix(16))" }

    // MARK: The sheet: cursor, page breaks, footer

    /// A face at a size, the Paint of the Android sheet: sans or mono, regular or bold, in ink or grey.
    struct Ink {
        let font: UIFont
        let colour: UIColor
        var size: CGFloat { font.pointSize }

        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }

        var attributes: [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: colour] }
    }

    final class Sheet {
        let s: Str
        let reference: String
        let total: Int
        let renderer: UIGraphicsPDFRenderer
        private var context: UIGraphicsPDFRendererContext?
        private let data = NSMutableData()
        private var consumer: CGDataConsumer?
        private var pdf: CGContext?
        var y: CGFloat = 0
        var pageNo = 0
        private var pageOpen = false

        let black = UIColor.black
        let grey = UIColor(red: 90 / 255, green: 90 / 255, blue: 90 / 255, alpha: 1)
        let titleInk: Ink
        let section: Ink
        let label: Ink
        let value: Ink
        let body: Ink
        let small: Ink
        let ruleColour = UIColor(red: 200 / 255, green: 200 / 255, blue: 200 / 255, alpha: 1)

        init(s: Str, reference: String, total: Int) {
            self.s = s
            self.reference = reference
            self.total = total
            renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: a4))
            titleInk = Ink(font: .monospacedSystemFont(ofSize: 40, weight: .bold), colour: black)
            section = Ink(font: .systemFont(ofSize: 26, weight: .bold), colour: black)
            label = Ink(font: .systemFont(ofSize: 20), colour: grey)
            value = Ink(font: .monospacedSystemFont(ofSize: 22, weight: .regular), colour: black)
            body = Ink(font: .systemFont(ofSize: 21), colour: black)
            small = Ink(font: .systemFont(ofSize: 17), colour: grey)
            guard let consumer = CGDataConsumer(data: data), let pdf = CGContext(consumer: consumer, mediaBox: nil, nil) else { return }
            self.consumer = consumer
            self.pdf = pdf
        }

        var canvas: CGContext? { pdf }

        func newPage() {
            finish()
            pageNo += 1
            guard let pdf else { return }
            var box = CGRect(origin: .zero, size: a4)
            pdf.beginPage(mediaBox: &box)
            // PDF space runs upward from the bottom left; the sheet is drawn top down in its own
            // units, so the page is flipped and scaled once here and every drawing call below
            // reads exactly like the Android one.
            pdf.translateBy(x: 0, y: a4.height)
            pdf.scaleBy(x: a4.width / pageWidth, y: -a4.height / pageHeight)
            pdf.setFillColor(UIColor.white.cgColor)
            pdf.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
            pageOpen = true
            y = margin
        }

        func finish() {
            guard pageOpen, let pdf else { return }
            // The footer: the instrument's name and the page, quietly.
            line(margin, pageHeight - foot - 14, pageWidth - margin, pageHeight - foot - 14, ruleColour, 1.5)
            text("Limen · \(reference)", margin, pageHeight - foot + 8, small)
            let pageText = total > 0 ? "\(s.pdfPage) \(pageNo) / \(total)" : "\(s.pdfPage) \(pageNo)"
            text(pageText, pageWidth - margin - small.width(pageText), pageHeight - foot + 8, small)
            pdf.endPage()
            pageOpen = false
        }

        func close() -> (data: Data, pages: Int) {
            finish()
            pdf?.closePDF()
            return (data as Data, pageNo)
        }

        /// Guarantees `need` vertical units, breaking the page when they are not there.
        func ensure(_ need: CGFloat) {
            if !pageOpen || y + need > pageHeight - foot - 30 { newPage() }
        }

        func gap(_ v: CGFloat) { y += v }

        /// Draws with the baseline at `baseline`, the way Canvas.drawText places its text.
        func text(_ string: String, _ x: CGFloat, _ baseline: CGFloat, _ ink: Ink) {
            guard let pdf else { return }
            UIGraphicsPushContext(pdf)
            // Core Text draws glyphs upright in a bottom-up space; the page above was flipped, so
            // each string is drawn through a local flip around its own baseline.
            pdf.saveGState()
            pdf.translateBy(x: x, y: baseline)
            pdf.scaleBy(x: 1, y: -1)
            (string as NSString).draw(at: CGPoint(x: 0, y: -ink.font.ascender), withAttributes: ink.attributes)
            pdf.restoreGState()
            UIGraphicsPopContext()
        }

        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ colour: UIColor, _ width: CGFloat) {
            guard let pdf else { return }
            pdf.setStrokeColor(colour.cgColor)
            pdf.setLineWidth(width)
            pdf.move(to: CGPoint(x: x1, y: y1))
            pdf.addLine(to: CGPoint(x: x2, y: y2))
            pdf.strokePath()
        }

        func image(_ image: CGImage, in rect: CGRect) {
            guard let pdf else { return }
            pdf.saveGState()
            pdf.translateBy(x: rect.minX, y: rect.maxY)
            pdf.scaleBy(x: 1, y: -1)
            pdf.interpolationQuality = .high
            pdf.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
            pdf.restoreGState()
        }

        func sectionTitle(_ title: String) {
            ensure(60)
            gap(16)
            text(title.uppercased(), margin, y + section.size, section)
            y += section.size + 8
            line(margin, y, pageWidth - margin, y, ruleColour, 1.5)
            gap(10)
        }

        func labeledRow(_ pairs: [(String, String)]) {
            let width = (pageWidth - 2 * margin) / CGFloat(pairs.count)
            let columns = pairs.map { heading, entry in
                (wrapLines(heading, label, width - 18), wrapLines(entry.ifBlank("–"), value, width - 18))
            }
            let labelLines = columns.map { $0.0.count }.max() ?? 0
            let valueLines = columns.map { $0.1.count }.max() ?? 0
            let labelStep = label.size + 5
            let valueStep = value.size + 6
            let need = CGFloat(labelLines) * labelStep + CGFloat(valueLines) * valueStep + 14
            ensure(need)
            for (index, column) in columns.enumerated() {
                let x = margin + CGFloat(index) * width
                for (line, string) in column.0.enumerated() {
                    text(string, x, y + label.size + CGFloat(line) * labelStep, label)
                }
                let valueTop = y + CGFloat(labelLines) * labelStep
                for (line, string) in column.1.enumerated() {
                    text(string, x, valueTop + value.size + CGFloat(line) * valueStep, value)
                }
            }
            y += need
        }

        func wrapped(_ string: String, _ ink: Ink, x: CGFloat = margin, width: CGFloat = pageWidth - 2 * margin) {
            for line in wrapLines(string, ink, width) {
                ensure(ink.size + 10)
                text(line, x, y + ink.size, ink)
                y += ink.size + 7
            }
        }

        func ellipsize(_ string: String, _ ink: Ink, _ width: CGFloat) -> String {
            if ink.width(string) <= width { return string }
            var t = string
            while !t.isEmpty, ink.width("\(t)…") > width { t.removeLast() }
            return "\(t)…"
        }

        func wrapLines(_ string: String, _ ink: Ink, _ width: CGFloat) -> [String] {
            var out: [String] = []
            for paragraph in string.split(separator: "\n", omittingEmptySubsequences: false) {
                var line = ""
                for word in paragraph.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                    if ink.width(word) > width {
                        if !line.isEmpty {
                            out.append(line)
                            line = ""
                        }
                        var chunks: [String] = []
                        var chunk = ""
                        for character in word {
                            let probe = chunk + String(character)
                            if !chunk.isEmpty, ink.width(probe) > width {
                                chunks.append(chunk)
                                chunk = String(character)
                            } else {
                                chunk = probe
                            }
                        }
                        if !chunk.isEmpty { chunks.append(chunk) }
                        out.append(contentsOf: chunks.dropLast())
                        line = chunks.last ?? ""
                        continue
                    }
                    let probe = line.isEmpty ? word : "\(line) \(word)"
                    if ink.width(probe) <= width {
                        line = probe
                    } else {
                        if !line.isEmpty { out.append(line) }
                        line = word
                    }
                }
                out.append(line)
            }
            return out
        }
    }

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
            sheet.labeledRow([(s.cantonLabel, s.canton(canton)), (s.legalBasis, s.legalProfile(p.legalProfile()))])
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
        sheet.sectionTitle(s.pdfFinalized)
        sheet.wrapped("\(s.fingerprint): \(p.evidenceFingerprint)", sheet.small)
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
        if p.deposit.kind == .none { return }
        sheet.sectionTitle(s.deposit)
        switch p.deposit.kind {
        case .insurance:
            sheet.labeledRow([(s.depositProvider, p.deposit.provider), (s.depositPolicy, p.deposit.policyNo), (s.depositAmount, p.deposit.amountChf)])
        case .bankAccount:
            sheet.labeledRow([(s.depositBankName, p.deposit.bank), (s.depositAccount, p.deposit.account), (s.depositAmount, p.deposit.amountChf)])
        case .none:
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
        sheet.wrapped(s.inkEvidenceNotice, sheet.small)

        // The Swiss ritual, said on the document itself: two identical papers, one per party. In
        // Vaud the RULV require exactly that, and a tenant who reads it here knows to leave the
        // flat holding one.
        sheet.gap(6)
        sheet.wrapped(s.pdfTwoCopies, sheet.small)
    }

    private static func drawPlane(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str, _ dir: URL, _ plane: Plane) {
        let sigs = p.signatures.filter { $0.plane == plane && p.isCurrent($0) }
        if sigs.isEmpty {
            sheet.wrapped(s.notSigned, sheet.body)
            return
        }
        for sig in sigs {
            sheet.ensure(190)
            let x = margin
            if sig.refused {
                sheet.text(s.refusedNote.uppercased(), x, sheet.y + sheet.value.size, sheet.value)
                sheet.y += sheet.value.size + 6
            } else if !sig.file.isBlank, let image = PhotoDecode.sampled(dir.appendingPathComponent(sig.file), targetWidth: 840) {
                let maxW: CGFloat = 420
                let maxH: CGFloat = 130
                let scale = min(maxW / CGFloat(image.width), maxH / CGFloat(image.height), 1)
                let w = CGFloat(image.width) * scale
                let h = CGFloat(image.height) * scale
                sheet.image(image, in: CGRect(x: x, y: sheet.y, width: w, height: h))
                sheet.y += h + 4
            }
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
            var detail: [String] = [s.role(receipt.role), s.deliveryMethod(receipt.method)]
            if receipt.epochMs > 0 { detail.append(formatMoment(receipt.epochMs)) }
            if !receipt.note.isBlank { detail.append(receipt.note) }
            sheet.wrapped(detail.joined(separator: " · "), sheet.body)
        }
    }

    private static func release(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str) {
        if p.kind != .exit || p.deposit.kind == .none { return }
        let releaseText: String
        switch p.deposit.kind {
        case .bankAccount: releaseText = s.releaseBank
        case .insurance: releaseText = s.releaseInsurance
        case .none: releaseText = ""
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
        case .none:
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
        let plates = Report.plates(p)
        if plates.isEmpty { return }
        let cellW = (pageWidth - 2 * margin - 40) / 2
        let cellH: CGFloat = 420
        // Whether a plate decodes, which the counting pass and the rendering pass must answer
        // identically or the printed "page N of M" lies about a document already signed.
        let readablePlates = plates.filter { PhotoDecode.readable(photoDir.appendingPathComponent($0.file)) }
        if readablePlates.isEmpty { return }
        sheet.ensure(cellH + 120)
        sheet.sectionTitle(s.pdfDefectAnnex)
        var col = 0
        for plate in readablePlates {
            let file = photoDir.appendingPathComponent(plate.file)
            // The counting pass reads the dimensions only: same page breaks, no decoding.
            let image = measuring ? nil : PhotoDecode.sampled(file, targetWidth: Int(cellW))
            if measuring ? PhotoDecode.readable(file) : image != nil {
                if col == 0 { sheet.ensure(cellH + 50) }
                let x = margin + CGFloat(col) * (cellW + 40)
                if let image {
                    let scale = min(cellW / CGFloat(image.width), (cellH - 40) / CGFloat(image.height))
                    let w = CGFloat(image.width) * scale
                    let h = CGFloat(image.height) * scale
                    sheet.image(image, in: CGRect(x: x, y: sheet.y, width: w, height: h))
                    var text = caption(plate, s)
                    if !plate.sha256.isBlank { text += " · \(plate.sha256.prefix(12))" }
                    sheet.text(sheet.ellipsize(text, sheet.small, cellW), x, sheet.y + h + sheet.small.size + 6, sheet.small)
                }
                col += 1
                if col == 2 {
                    col = 0
                    sheet.y += cellH + 20
                }
            }
        }
        if col != 0 { sheet.y += cellH + 20 }
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
