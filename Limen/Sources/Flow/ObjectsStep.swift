import LimenKit
import SwiftUI

/// Everything handed over with the flat, one row per thing.
///
/// A row rather than a toggle, because two fridges in a kitchen are two facts and each needs its
/// own condition, evidence and findings. The camera sits on the row itself.
struct ObjectsStep: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    @State private var addingCategory = false
    @State private var categoryDraft = ""
    // A category the operator has named but not yet filled. Held here rather than written to the
    // record: creating it used to add an object row labelled after the category itself, so the
    // paper listed a supplied item that was never supplied, under a heading of the same name.
    @State private var pendingGroups: [String] = []

    var body: some View {
        let recorded = model.customGroups(p)
        let customGroups = (recorded + pendingGroups.filter { !recorded.contains($0) }).distinct()
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ObjectGroupPanel(p: p, label: s.appliances, group: .appliance, groupLabel: "", catalogue: Appliance.allCases.map { ($0.rawValue, s.appliance($0)) })
                ObjectGroupPanel(p: p, label: s.furnitureLabel, group: .furniture, groupLabel: "", catalogue: Furniture.allCases.map { ($0.rawValue, s.furniture($0)) })
                // Anything the two shipped lists have no word for: garden tools, a bicycle rack, the
                // ski cellar's shelving. The person names the category and it behaves like the others.
                ForEach(customGroups, id: \.self) { name in
                    ObjectGroupPanel(p: p, label: name, group: .other, groupLabel: name, catalogue: [])
                }
                if !locked {
                    RoomActionKey(label: s.addCategory, fill: colors.positive, outline: colors.positive, text: colors.onPositive, glyph: .add) { addingCategory.toggle() }
                }
                if addingCategory, !locked {
                    Panel(label: s.addCategory) {
                        VStack(alignment: .leading, spacing: 8) {
                            Field(label: s.categoryName, value: categoryDraft) { categoryDraft = $0 }
                            SmallKey(label: s.add, enabled: !categoryDraft.trimmingCharacters(in: .whitespaces).isEmpty, stretch: true) {
                                let name = categoryDraft.trimmingCharacters(in: .whitespaces)
                                // The heading appears; nothing is written to the record until a row is
                                // added under it. An empty category is not a fact about the flat.
                                if !name.isBlank, !customGroups.contains(name) { pendingGroups.append(name) }
                                categoryDraft = ""
                                addingCategory = false
                            }
                        }
                    }
                }
                BigKey(label: s.stepDossier.uppercased()) { model.goTo(.dossier) }
                Spacer().frame(height: 12)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct ObjectGroupPanel: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    let label: String
    let group: ObjectGroup
    let groupLabel: String
    let catalogue: [(String, String)]
    @State private var freeDraft = ""

    var body: some View {
        let rows = p.objects.filter { $0.group == group && (group != .other || $0.groupLabel == groupLabel) }
        // A group nobody filled in is not part of a signed record, so it is not shown on one.
        if !(locked && rows.isEmpty) {
            Panel(label: label) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows, id: \.id) { entry in ObjectRow(p: p, entry: entry) }
                    // Pressing a catalogue key appends: the same key twice records two of the thing.
                    if !catalogue.isEmpty, !locked {
                        FlowRow(spacing: 6) {
                            ForEach(catalogue, id: \.0) { name, shown in
                                Chip(label: "+ \(shown)", dim: false) { model.addObject(group, catalogue: name, groupLabel: groupLabel) }
                            }
                        }
                    }
                    if !locked {
                        HStack(alignment: .top, spacing: 8) {
                            Field(label: s.addObject, value: freeDraft) { freeDraft = $0 }
                            SmallKey(label: s.add, enabled: !freeDraft.trimmingCharacters(in: .whitespaces).isEmpty) {
                                model.addObject(group, label: freeDraft.trimmingCharacters(in: .whitespaces), groupLabel: groupLabel)
                                freeDraft = ""
                            }
                        }
                    }
                }
            }
        }
    }
}

/// One supplied thing: what it is, what it looks like today, and any finding about it.
private struct ObjectRow: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    let entry: ObjectEntry

    var body: some View {
        let defects = p.defects.filter { $0.objectId == entry.id }
        let flagged = !defects.isEmpty
        let evidenceFiles = entry.photoFiles()
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.displayName(s)).font(LimenType.rowTitle).foregroundStyle(colors.ink)
                    Text(p.rooms.first { $0.id == entry.roomId }.map { $0.name.ifBlank(s.room($0.kind)) } ?? s.wholeFlat)
                        .font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !locked {
                    PhotoIntakeKeys(compact: true, owner: entry.id, kind: .object) { file, source in model.attachObjectPhoto(entry.id, source: file, photoSource: source) }
                    IconKey(glyph: .add, label: s.addDefect, fillColor: flagged ? colors.warning : nil, outlineColor: flagged ? colors.warningOutline : nil, tint: flagged ? colors.warningOutline : nil) {
                        model.openObjectDefect(entry.id)
                    }
                    IconKey(glyph: .delete, label: s.delete, destructive: true, tick: .reject) { model.removeObject(entry.id) }
                }
            }
            Field(label: s.objectNote, value: entry.note) { value in
                model.updateObject(entry.id) { var x = $0; x.note = value; return x }
            }
            Toggle(label: s.objectInspected, on: entry.inspected, enabled: !locked) { model.setObjectInspected(entry.id, !entry.inspected) }
            if !entry.inspected { ScopeNote(p: p, key: entry.id) }
            if !evidenceFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(evidenceFiles, id: \.self) { name in
                            PhotoThumb(name: name, size: 84, evidence: entry.photoEvidence.first { $0.file == name }) { model.removeObjectPhoto(entry.id, name: name) }
                        }
                    }
                }
            }
            if !defects.isEmpty {
                VStack(spacing: 5) {
                    ForEach(defects, id: \.id) { defect in
                        if locked {
                            DefectLine(p: p, d: defect)
                        } else {
                            DismissibleItemRow(onRemove: { model.removeDefect(defect.id) }) { DefectLine(p: p, d: defect) }
                        }
                    }
                }
            }
            // Which room it stands in, when that matters. Blank is the honest default: most of what
            // is supplied belongs to the flat rather than to one of its rooms.
            if !p.rooms.isEmpty, !locked {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        Chip(label: s.wholeFlat, active: entry.roomId.isBlank) {
                            model.updateObject(entry.id) { var x = $0; x.roomId = ""; return x }
                        }
                        ForEach(p.rooms, id: \.id) { room in
                            Chip(label: room.name.ifBlank(s.room(room.kind)), active: entry.roomId == room.id) {
                                model.updateObject(entry.id) { var x = $0; x.roomId = room.id; return x }
                            }
                        }
                    }
                }
            }
            Spacer().frame(height: 2)
        }
    }
}
