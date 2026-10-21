import Foundation

/// Everything supplied with the flat, grouped the way it was entered: one panel per group, one
/// row per object with its chips, and the findings on that object right under it.
extension PdfExport.Sheet {
    func objects(_ p: HandoverProtocol) {
        if !Outline.objects(p) { return }
        heading(s.objects)
        // Both, when a record carries both. Returning after the legacy block only while objects
        // was empty meant adding one row to a seeded exit dropped the whole inherited inventory.
        if Outline.legacyObjects(p) {
            let appliances = p.extras.appliances.sorted { $0.ordinal < $1.ordinal }.map(s.appliance) + p.extras.customAppliances
            let furniture = p.extras.furniture.sorted { $0.ordinal < $1.ordinal }.map(s.furniture) + p.extras.customFurniture
            var blocks: [any PdfExport.Block] = []
            if !appliances.isEmpty {
                blocks.append(PdfExport.Text(s.appliances, .labelSmall, keepWithNext: true))
                blocks.append(PdfExport.Chips(appliances.map { PdfExport.Chip($0) }))
            }
            if !furniture.isEmpty {
                blocks.append(PdfExport.Text(s.furnitureLabel, .labelSmall, keepWithNext: true))
                blocks.append(PdfExport.Chips(furniture.map { PdfExport.Chip($0) }))
            }
            panel(PdfExport.Panel(s.objects, blocks, inContents: false))
        }
        let onObjects = Report.objectFindings(p)
        var groups: [(ObjectGroup, String)] = []
        for entry in p.objects where !groups.contains(where: { $0.0 == entry.group && $0.1 == entry.groupLabel }) {
            groups.append((entry.group, entry.groupLabel))
        }
        for (group, groupLabel) in groups {
            var blocks: [any PdfExport.Block] = []
            for entry in p.objects where entry.group == group && entry.groupLabel == groupLabel {
                blocks.append(PdfExport.Text(entry.displayName(s), .bodyMedium, keepWithNext: true))
                var chips = [PdfExport.Chip(entry.inspected ? s.objectInspected : s.notInspected, active: entry.inspected)]
                if let room = p.rooms.first(where: { $0.id == entry.roomId }) { chips.append(PdfExport.Chip(Outline.roomName(room, s))) }
                if !entry.photos.isEmpty { chips.append(PdfExport.Chip("\(s.photos): \(entry.photos.count)")) }
                blocks.append(PdfExport.Chips(chips))
                if !entry.note.isBlank { blocks.append(PdfExport.Text(entry.note, .small)) }
                for numbered in onObjects where numbered.defect.objectId == entry.id { blocks.append(findingBlock(p, numbered)) }
                blocks.append(PdfExport.Gap(PdfTokens.labelGap))
            }
            panel(PdfExport.Panel(groupLabel.ifBlank(s.objectGroup(group)), blocks, inContents: false))
        }
    }
}
