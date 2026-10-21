import Foundation

/// One numbered finding as a block: where it was found, its words, the facts hanging on it as
/// chips, the charge first and in the active colour because Art. 267a OR makes it the column a
/// court reads, and each participant's position.
extension PdfExport.Sheet {
    func findingBlock(_ p: HandoverProtocol, _ numbered: Report.Numbered) -> PdfExport.Finding {
        let d = numbered.defect
        var wherePieces: [String] = []
        if !d.objectId.isBlank, let entry = p.objects.first(where: { $0.id == d.objectId }) { wherePieces.append(entry.displayName(s)) }
        if let item = p.defectItemLabel(d, s) { wherePieces.append(item) }
        var chips: [PdfExport.Chip] = []
        if d.chargedToTenant { chips.append(PdfExport.Chip(s.chargedToTenant, active: true)) }
        switch d.fixBy {
        case .tenant: chips.append(PdfExport.Chip("\(s.fixByLabel): \(s.role(.tenant))"))
        case .landlord: chips.append(PdfExport.Chip("\(s.fixByLabel): \(s.role(.landlord))"))
        case .open: break
        }
        if !d.fixDeadline.isBlank { chips.append(PdfExport.Chip("\(s.fixDeadline) \(SwissDate.display(d.fixDeadline))")) }
        if !d.photos.isEmpty { chips.append(PdfExport.Chip("\(s.photos): \(d.photos.count)")) }
        if d.tenantResponse != .notStated { chips.append(PdfExport.Chip("\(s.tenantResponseLabel): \(s.tenantResponse(d.tenantResponse))")) }
        var notes: [String] = []
        if !d.costNote.isBlank { notes.append("\(s.costNote): \(d.costNote)") }
        if !d.reservation.isBlank { notes.append("\(s.reservationLabel): \(d.reservation)") }
        if !d.tenantComment.isBlank { notes.append("\(s.tenantComment): \(d.tenantComment)") }
        let positions = d.participantPositions.entries.map { id, position -> String in
            let name = p.parties.first { $0.participantKey() == id }?.name ?? id
            return "\(name): \(s.tenantResponse(position.response))\n\(position.comment)"
        }
        return PdfExport.Finding(number: numbered.number, where: wherePieces.joined(separator: ", "), text: d.text, chips: chips, notes: notes, positions: positions)
    }

    /// Findings with no panel to sit in: a finding whose room is gone, or one on an object the
    /// record no longer lists. Either would otherwise vanish from the paper while still counting
    /// in the record and carrying a caption in the annex.
    func strayFindings(_ p: HandoverProtocol) {
        let strays = Outline.strays(p)
        if strays.isEmpty { return }
        panel(PdfExport.Panel(s.defects, strays.map { findingBlock(p, $0) }))
    }
}
