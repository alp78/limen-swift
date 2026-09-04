import LimenKit
import SwiftUI

/// The inspection: a grid of rooms and, inside one, its findings.
///
/// No forced walking order. People go through a flat in the order it is built, explicitly confirm
/// each room they inspect, and add as many findings as its condition requires.
struct InspectionStep: View {
    @Environment(LimenModel.self) private var model
    let p: HandoverProtocol

    var body: some View {
        if let id = model.openRoomId, let room = p.rooms.first(where: { $0.id == id }) {
            RoomDetail(p: p, room: room).id(room.id)
        } else {
            RoomGrid(p: p)
        }
    }
}

private struct RoomGrid: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    @State private var addingRoom = false
    @State private var customName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !locked, p.rooms.isEmpty, !p.roomSetupComplete {
                    InitialRoomSetup(p: p)
                    Spacer().frame(height: 12)
                } else {
                    FlowRow(spacing: 8) {
                        ForEach(p.rooms, id: \.id) { room in
                            RoomKey(label: room.name.ifBlank(s.room(room.kind)), defects: p.defects.filter { $0.roomId == room.id }.count, inspected: room.inspected) {
                                model.openRoom(room.id)
                            }
                        }
                    }
                    if !locked {
                        RoomActionKey(label: s.addRoom, fill: colors.positive, outline: colors.positive, text: colors.onPositive, glyph: .add) { addingRoom.toggle() }
                    }
                    if addingRoom, !locked {
                        Panel(label: s.addRoom) {
                            VStack(alignment: .leading, spacing: 8) {
                                // Every kind, not a chosen nine: a flat that has a wine cellar and no
                                // balcony should not have to call the cellar a balcony.
                                FlowRow(spacing: 6) {
                                    ForEach(RoomKind.allCases.filter { $0 != .custom }, id: \.self) { kind in
                                        Chip(label: s.room(kind)) {
                                            model.addRoom(kind)
                                            addingRoom = false
                                        }
                                    }
                                }
                                // A room the canon has no word for: the freezing room, the darkroom, the workshop.
                                Field(label: s.roomName, value: customName, hint: s.room(.custom)) { customName = $0 }
                                SmallKey(label: s.add, enabled: !customName.trimmingCharacters(in: .whitespaces).isEmpty, stretch: true) {
                                    model.addRoom(.custom, name: customName)
                                    customName = ""
                                    addingRoom = false
                                }
                            }
                        }
                    }
                    SmallKey(label: s.stepObjects.uppercased(), stretch: true) { model.goTo(.objects) }
                    Spacer().frame(height: 12)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct InitialRoomSetup: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let p: HandoverProtocol
    @State private var selected: Set<RoomKind> = []

    var body: some View {
        Panel(label: s.chooseRoomsPresent) {
            VStack(alignment: .leading, spacing: 10) {
                Text(s.chooseRoomsPresentBody).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                FlowRow(spacing: 6) {
                    ForEach(Templates.defaultRooms, id: \.self) { kind in
                        let active = selected.contains(kind)
                        Chip(label: s.room(kind), active: active, selectionState: active) {
                            if active { selected.remove(kind) } else { selected.insert(kind) }
                        }
                    }
                }
                HStack(spacing: 8) {
                    SmallKey(label: s.selectAll, stretch: true) { selected = Set(Templates.defaultRooms) }
                    SmallKey(label: s.clear, enabled: !selected.isEmpty, stretch: true) { selected = [] }
                }
                BigKey(label: s.useSelectedRooms, active: !selected.isEmpty, enabled: !selected.isEmpty) {
                    model.setInitialRooms(Templates.defaultRooms.filter { selected.contains($0) })
                }
            }
        }
        .onChange(of: p.id) { _, _ in selected = [] }
    }
}

/// A room on the grid: its name, and how many findings it holds, amber when it holds any.
private struct RoomKey: View {
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let label: String
    let defects: Int
    let inspected: Bool
    let onPress: () -> Void

    var body: some View {
        let flagged = defects > 0
        let state: String = flagged ? "! \(defects)\(inspected ? " · ✓" : "")" : (inspected ? "✓ \(s.inspectedNoDefects)" : s.notInspected)
        KeySurface(radius: 12, fillColor: flagged ? colors.warning : colors.plateRaised, outlineColor: flagged ? colors.warningOutline : colors.actionOutline, accessibilityLabel: label, onPress: onPress) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(LimenType.rowTitle).lineLimit(2).foregroundStyle(colors.ink).multilineTextAlignment(.leading)
                Text(state)
                    .font(LimenType.mono(13, flagged ? .bold : .regular, like: .footnote))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(flagged ? colors.dangerOutline : (inspected ? colors.seal : colors.inkDim))
            }
            .padding(12)
            .frame(width: 164, alignment: .leading)
        }
        .frame(width: 164)
    }
}

private struct RoomDetail: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    let room: Room
    @State private var confirmingClear = false
    @State private var confirmingRemove = false

    var body: some View {
        let roomDefects = p.defects.filter { $0.roomId == room.id }
        let entryRoom = model.entryBaseline?.rooms.first { $0.id == room.id }
        let entryDefects = model.entryBaseline?.defects.filter { $0.roomId == room.id }.count ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Back on the left, where the other back keys in the app are.
                HStack(spacing: 8) {
                    IconKey(glyph: .back, label: s.back) { model.closeRoom() }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(room.name.ifBlank(s.room(room.kind)).uppercased()).font(LimenType.titleMedium).foregroundStyle(colors.ink)
                        if entryRoom != nil, entryDefects > 0 {
                            Text("\(s.atEntry): \(s.countDefects(entryDefects))").font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // Only a room the canon has no word for needs naming; the rest are named already.
                if room.kind == .custom {
                    Field(label: s.roomName, value: room.name) { model.renameRoom(room.id, name: $0) }
                }
                Toggle(label: s.roomInspected, on: room.inspected, enabled: !locked) { model.setRoomInspected(room.id, !room.inspected) }
                if !locked {
                    ItemPicker(kind: room.kind) { key, label in model.openDefect(room.id, item: key, itemLabel: label) }
                }
                if roomDefects.isEmpty {
                    Text(room.inspected ? s.inspectedNoDefects : s.roomClean)
                        .font(LimenType.bodyMedium)
                        .foregroundStyle(room.inspected ? colors.seal : colors.inkDim)
                } else {
                    Panel(label: "\(s.defects) (\(roomDefects.count))", warning: true) {
                        VStack(spacing: 6) {
                            ForEach(roomDefects, id: \.id) { d in
                                if locked {
                                    DefectLine(p: p, d: d)
                                } else {
                                    DismissibleItemRow(onRemove: { model.removeDefect(d.id) }) { DefectLine(p: p, d: d) }
                                }
                            }
                        }
                    }
                }
                // An older record still shows the grid it was signed with, read only: those grades
                // are part of what the parties agreed to and this version has no way to change them.
                if room.hasLegacyGrid {
                    Panel(label: s.atEntry) {
                        VStack(spacing: 2) {
                            ForEach(Array(room.items.enumerated()), id: \.offset) { _, item in
                                HStack {
                                    Text(item.key == .custom && !item.label.isBlank ? item.label : s.item(item.key)).font(LimenType.labelSmall).foregroundStyle(colors.inkDim).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(s.gradeShort(item.grade)).font(LimenType.mono(12)).foregroundStyle(colors.inkDim)
                                }
                            }
                        }
                    }
                }
                if !locked {
                    HStack(spacing: 8) {
                        RoomActionKey(label: s.clearRoom, fill: colors.danger, outline: colors.dangerOutline, text: colors.dangerOutline, glyph: .clear) { confirmingClear = true }
                        RoomActionKey(label: s.removeRoom, fill: colors.danger, outline: colors.dangerOutline, text: colors.dangerOutline, glyph: .delete) { confirmingRemove = true }
                    }
                }
                Spacer().frame(height: 12)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .confirmDialog($confirmingClear, body: s.clearRoomBody) { model.clearRoom(room.id) }
        .confirmDialog($confirmingRemove, body: s.removeRoomBody) { model.removeRoom(room.id) }
    }
}

/// The way a finding starts: pick what it is about, then write it.
///
/// The list is this room's template, which is now a catalogue to choose from rather than a
/// checklist to work through. Anything it does not name is typed instead, so the vocabulary never
/// becomes the limit on what can be recorded.
private struct ItemPicker: View {
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let kind: RoomKind
    let onPick: (ItemKey, String) -> Void
    @State private var namingOther = false
    @State private var otherName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(Templates.itemsFor(kind), id: \.self) { item in
                    Button(s.item(item)) { onPick(item, "") }
                }
                Button(s.otherItem) { namingOther = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: ButtonGlyph.add.symbol).font(.system(size: 18, weight: .medium))
                    Text(s.recordDefect).font(LimenType.labelLarge).tracking(0.4).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                }
                .foregroundStyle(colors.warningOutline)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity)
                .background(colors.warning, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(colors.warningOutline, lineWidth: 1))
            }
            .accessibilityLabel(s.recordDefect)
            if namingOther {
                Panel(label: s.otherItem) {
                    VStack(alignment: .leading, spacing: 8) {
                        Field(label: s.otherItemName, value: otherName, hint: s.pickItem) { otherName = $0 }
                        HStack(spacing: 8) {
                            SmallKey(label: s.cancel, stretch: true) {
                                namingOther = false
                                otherName = ""
                            }
                            SmallKey(label: s.add, enabled: !otherName.trimmingCharacters(in: .whitespaces).isEmpty, stretch: true) {
                                onPick(.custom, otherName.trimmingCharacters(in: .whitespaces))
                                otherName = ""
                                namingOther = false
                            }
                        }
                    }
                }
            }
        }
    }
}
