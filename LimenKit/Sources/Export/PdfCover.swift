import CoreGraphics
import Foundation

/// Page 1: the landing's navy field with the seal, the name and what this record is, then the
/// facts a reader wants first, the property, the parties, the record's status, and the contents
/// with each section's page. `pages` are the counting pass's, or nil while counting.
extension PdfExport.Sheet {
    private static let bannerBottom: CGFloat = 510

    func cover(_ p: HandoverProtocol, planned: [Outline.Entry], pages: [Int]?) {
        newPage(cover: true)
        let margin = PdfTokens.margin
        let kind = p.kind == .entry ? s.entry : s.exit
        let moment = [SwissDate.display(p.handoverDate), p.handoverTime].filter { !$0.isBlank }.joined(separator: " ")
        let canton = p.objectCanton.map { s.canton($0) } ?? ""

        fillRound(CGRect(x: margin, y: margin, width: PdfTokens.width - 2 * margin, height: Self.bannerBottom - margin), radius: PdfTokens.bannerRadius, paints.navyFill)
        if let logo { image(logo, in: CGRect(x: 138, y: 146, width: 128, height: 128)) }
        text("LIMEN", 306, 216, paints.display)
        text(s.protocolKind.uppercased(), 306, 252, paints.labelLarge.tinted(PdfTokens.onNavyDim))
        pill(PdfExport.Pill(kind, .paper), right: PdfTokens.width - margin - 48, top: 146)
        let address = paints.title.tinted(PdfTokens.paper)
        let dim = paints.bodyLarge.tinted(PdfTokens.onNavyDim)
        let paper = paints.bodyLarge.tinted(PdfTokens.paper)
        let rightX = PdfTokens.width - margin - 48
        let momentWidth = paper.width(moment)
        let cantonWidth = dim.width(canton)
        let leftMax = rightX - max(momentWidth, cantonWidth) - 40 - 138
        text(PdfExport.TextMeasure.ellipsize(p.address, address, leftMax), 138, 400, address)
        text(PdfExport.TextMeasure.ellipsize(p.place, dim, leftMax), 138, 440, dim)
        text(moment, rightX - momentWidth, 400, paper)
        text(canton, rightX - cantonWidth, 440, dim)
        html?.banner("Limen", ["\(s.protocolKind): \(kind)", p.address, p.place, moment, canton])
        y = Self.bannerBottom + 40

        panel(PdfExport.Panel(s.objectLabel, property(p, moment), inContents: false))
        panel(PdfExport.Panel(s.parties, parties(p), inContents: false))
        let status = p.isFinalized() ? PdfExport.Pill(s.pdfFinalized, .seal) : PdfExport.Pill(s.previewDraft, .dim)
        panel(PdfExport.Panel(s.stepRecord, self.status(p), pill: status, inContents: false))
        let entries = planned.enumerated().map { i, entry in PdfExport.Contents.Entry(title: entry.title, level: entry.level, anchor: anchor(i)) }
        panel(PdfExport.Panel(s.contents, [PdfExport.Contents(entries, pages: pages ?? Array(repeating: nil, count: planned.count))], inContents: false))
        // The body starts on a fresh page when the cover held everything; a contents that ran on
        // to a second page is followed by the body on that page rather than a blank one.
        if pageNo == 1 { newPage() }
    }

    private func property(_ p: HandoverProtocol, _ moment: String) -> [any PdfExport.Block] {
        var first: [(String, String)] = [(s.address, p.address), (s.place, p.place)]
        if let canton = p.objectCanton {
            first.append((s.cantonLabel, s.canton(canton)))
            first.append((s.legalBasis, s.legalProfile(p.legalProfile())))
        }
        var second: [(String, String)] = [(s.objectDetail, p.objectDetail), (s.handoverDate, moment)]
        if !p.lastProtocolDate.isBlank { second.append((s.lastProtocol, SwissDate.display(p.lastProtocolDate))) }
        return [PdfExport.Fields(first, columns: 2), PdfExport.Fields(second, columns: 2)]
    }

    private func parties(_ p: HandoverProtocol) -> [any PdfExport.Block] {
        var blocks: [any PdfExport.Block] = []
        for party in p.parties {
            blocks.append(PdfExport.Fields([(s.role(party.role), party.name)], columns: 1))
            if !party.representedBy.isBlank { blocks.append(PdfExport.Text("\(s.representedBy): \(party.representedBy)", .small)) }
            if !party.agency.isBlank { blocks.append(PdfExport.Text("\(s.actorAgency): \(party.agency)", .small)) }
            if !party.authority.isBlank { blocks.append(PdfExport.Text("\(s.authority): \(party.authority)", .small)) }
            if !party.phone.isBlank { blocks.append(PdfExport.Text(party.phone, .small)) }
            if !party.email.isBlank { blocks.append(PdfExport.Text(party.email, .small)) }
            if !party.address.isBlank { blocks.append(PdfExport.Text("\(s.newAddress): \(party.address)", .small)) }
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
            blocks.append(PdfExport.Gap(PdfTokens.labelGap))
            let side = p.sessionRole.map { " (\(s.role($0)))" } ?? ""
            blocks.append(PdfExport.Text("\(s.compiledBy)\(side)", .labelSmall, keepWithNext: true))
            for line in contact { blocks.append(PdfExport.Text(line, .small)) }
        }
        return blocks
    }

    /// The immutable record's reference and fingerprint and, when applicable, the record it corrects.
    private func status(_ p: HandoverProtocol) -> [any PdfExport.Block] {
        var blocks: [any PdfExport.Block] = [PdfExport.Fields([("Limen", reference)], columns: 1)]
        if !p.evidenceFingerprint.isBlank { blocks.append(PdfExport.Text("\(s.fingerprint): \(p.evidenceFingerprint)", .small)) }
        if !p.amendedFromId.isBlank {
            // By the reference the amended document actually prints on itself. The raw store id
            // appears on no PDF anywhere, so it identified nothing to a reader.
            let amended = p.amendedFromFingerprint.isBlank ? p.amendedFromId : "LIMEN-\(p.amendedFromFingerprint.prefix(16))"
            blocks.append(PdfExport.Text("\(s.pdfAmends): \(amended)", .small))
        }
        return blocks
    }
}
