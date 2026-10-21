import Foundation

/// The inspection: one panel per room, as the app shows one tile per room. A room with findings
/// is the amber warning panel and carries them, numbered, inside; a room without is the raised
/// panel with its status as the pill. The record-wide numbering is the contract with the annex,
/// so a finding's number here names the one under its photograph.
extension PdfExport.Sheet {
    func rooms(_ p: HandoverProtocol) {
        if p.rooms.isEmpty { return }
        heading(s.stepInspection)
        let sections = AnnexContent.sections(p, s)
        for room in p.rooms { panel(roomPanel(p, room, sections.first { $0.key == room.id })) }
    }

    private func roomPanel(_ p: HandoverProtocol, _ room: Room, _ section: AnnexContent.Section?) -> PdfExport.Panel {
        let found = Report.roomFindings(p, room.id)
        let pill: PdfExport.Pill
        if !found.isEmpty {
            pill = PdfExport.Pill(s.defectCount(found.count), .warning)
        } else if room.inspected {
            pill = PdfExport.Pill(s.roomInspected, .seal)
        } else {
            pill = PdfExport.Pill(s.notInspected, .dim)
        }
        var blocks: [any PdfExport.Block] = []
        // The room's readout first, as the hub door carries its own: how many photographs the
        // annex holds for it and on which page. A closing row would be stranded by a page break.
        if let section {
            blocks.append(PdfExport.Chips([PdfExport.Chip("\(s.photos): \(section.cards.count)"), PdfExport.Chip(annexPointer(section))], keepWithNext: true))
        }
        if room.hasLegacyGrid { blocks.append(PdfExport.ItemGrid(legacyGrid(p, room))) }
        // A room explicitly confirmed as inspected says so even with no finding. Legacy seeded
        // rooms stay labelled not inspected by their pill, so the paper never turns their
        // silence into a claim that somebody checked them.
        if found.isEmpty, room.inspected { blocks.append(PdfExport.Text(s.inspectedNoDefects, .body)) }
        for numbered in found { blocks.append(findingBlock(p, numbered)) }
        return PdfExport.Panel(Outline.roomName(room, s), blocks, pill: pill, tone: found.isEmpty ? .raised : .warning, level: 1, key: room.id)
    }

    /// Where a section's photographs are: its page once counted, the annex alone while counting.
    func annexPointer(_ section: AnnexContent.Section) -> String {
        annexPages[section.key].map { "\(s.pdfDefectAnnex): \(s.pdfPage) \($0)" } ?? s.pdfDefectAnnex
    }

    /// The exhaustive item grid, printed only for a record that was signed with one. The state
    /// names the findings on an item by number, as the grid always has.
    private func legacyGrid(_ p: HandoverProtocol, _ room: Room) -> [(String, String)] {
        room.items.map { item in
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
    }
}
