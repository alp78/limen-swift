import Foundation
import LimenKit

/// The rooms, the supplied objects, the dossier components and the findings: every edit to the
/// record's content, each through `edit`.
extension LimenModel {
    // MARK: Rooms

    func openRoom(_ roomId: String) {
        guard working?.rooms.contains(where: { $0.id == roomId }) == true else { return }
        openRoomId = roomId
        flowStep = .inspection
    }

    func closeRoom() { openRoomId = nil }

    func setInitialRooms(_ kinds: [RoomKind]) {
        if contentLocked || kinds.isEmpty || working?.rooms.isEmpty == false { return }
        let unique = kinds.distinct()
        edit { p in
            var next = p
            next.rooms = unique.enumerated().map { Room(id: "r\(p.createdEpochMs)-\($0.offset)", kind: $0.element) }
            next.roomSetupComplete = true
            return next
        }
    }

    func addRoom(_ kind: RoomKind, name: String = "") {
        let id = "r\(Self.now())"
        edit { p in
            var next = p
            next.rooms.append(Room(id: id, kind: kind, name: name.trimmingCharacters(in: .whitespacesAndNewlines)))
            return next
        }
        if working?.rooms.contains(where: { $0.id == id }) == true { openRoomId = id }
    }

    func renameRoom(_ roomId: String, name: String) {
        edit { p in
            var next = p
            next.rooms = p.rooms.map { room in
                var r = room
                if r.id == roomId { r.name = name }
                return r
            }
            return next
        }
    }

    func setRoomInspected(_ roomId: String, _ inspected: Bool) {
        edit { p in
            var next = p
            next.rooms = p.rooms.map { room in
                var r = room
                if r.id == roomId { r.inspected = inspected }
                return r
            }
            return next
        }
    }

    func removeRoom(_ roomId: String) {
        if contentLocked { return }
        let gone = working?.defects.filter { $0.roomId == roomId } ?? []
        deletePhotos(gone.flatMap { $0.photoFiles() })
        edit { p in
            var next = p
            next.rooms = p.rooms.filter { $0.id != roomId }
            next.defects = p.defects.filter { $0.roomId != roomId }
            next.objects = p.objects.map { entry in
                var e = entry
                if e.roomId == roomId { e.roomId = "" }
                return e
            }
            return next
        }
        if openRoomId == roomId { openRoomId = nil }
    }

    /// Clears every finding in this room, leaving the room itself on the walk.
    func clearRoom(_ roomId: String) {
        if contentLocked { return }
        let gone = working?.defects.filter { $0.roomId == roomId } ?? []
        deletePhotos(gone.flatMap { $0.photoFiles() })
        edit { p in
            var next = p
            next.defects = p.defects.filter { $0.roomId != roomId }
            return next
        }
    }

    // MARK: Objects

    /// Appends a row. Pressing the same catalogue key twice records two of the thing, because
    /// two fridges in a flat are two facts, each with its own photograph.
    func addObject(_ group: ObjectGroup, catalogue: String = "", label: String = "", groupLabel: String = "", roomId: String = "") {
        if group == .other, groupLabel.isBlank { return }
        if catalogue.isBlank, label.isBlank { return }
        edit { p in
            var next = p
            next.objects.append(ObjectEntry(
                id: "o\(Self.now())", group: group,
                groupLabel: groupLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                catalogue: catalogue, label: label.trimmingCharacters(in: .whitespacesAndNewlines), roomId: roomId
            ))
            return next
        }
    }

    func updateObject(_ id: String, _ transform: (ObjectEntry) -> ObjectEntry) {
        edit { p in
            var next = p
            next.objects = p.objects.map { $0.id == id ? transform($0) : $0 }
            return next
        }
    }

    func setObjectInspected(_ id: String, _ inspected: Bool) {
        updateObject(id) { entry in
            var e = entry
            e.inspected = inspected
            return e
        }
    }

    /// A removed object takes its photographs and any finding recorded on it with it.
    func removeObject(_ id: String) {
        if contentLocked { return }
        let entry = working?.objects.first { $0.id == id }
        let gone = working?.defects.filter { $0.objectId == id } ?? []
        reversibleEdit(.object, evidenceNames: (entry?.photoFiles() ?? []) + gone.flatMap { $0.photoFiles() }) { p in
            var next = p
            next.objects = p.objects.filter { $0.id != id }
            next.defects = p.defects.filter { $0.objectId != id }
            return next
        }
    }

    /// Every custom group on this record, in the order the person created them.
    func customGroups(_ p: HandoverProtocol? = nil) -> [String] {
        (p ?? working)?.objects.filter { $0.group == .other }.map(\.groupLabel).filter { !$0.isBlank }.distinct() ?? []
    }

    // MARK: The dossier

    func addDossierCard(_ card: DossierCard) { setDossier { $0 + [card] } }

    /// Removing a component takes its content with it, so the record never prints a stale field.
    func removeDossierCard(_ card: DossierCard) {
        setDossier { $0.filter { $0 != card } }
        edit { p in
            var next = p
            switch card {
            case .contract: next.contract = Contract()
            case .deposit:
                next.deposit = Deposit()
                next.legalOverlay = p.legalOverlay.withoutStatus(.depositProof)
            case .meters: next.meters = Meters()
            case .keys:
                next.keys = []
                next.selfMadeKeys = false
                next.keyTransfer = .notRecorded
                next.keyTransferNote = ""
            case .notes:
                // oneSided goes with it: it is edited on this card, it derives this card back at
                // dossierCards, and a record with no notes cannot state why it is one-sided.
                next.remarks = ""
                next.chargesStatementBy = ""
                next.oneSided = false
                next.unilateralReason = nil
                next.unilateralNote = ""
            }
            return next
        }
    }

    /// Seeds from the content-derived answer before applying the change, so a draft written
    /// before the dossier existed does not lose its deposit the moment a meter is added.
    func setDossier(_ transform: ([DossierCard]) -> [DossierCard]) {
        edit { p in
            var next = p
            next.dossier = transform(p.dossierCards()).distinct().sorted { $0.ordinal < $1.ordinal }
            next.dossierChosen = true
            return next
        }
    }

    // MARK: Defects

    func openDefect(_ roomId: String, item: ItemKey?, itemLabel: String = "") {
        if contentLocked { return }
        let id = "d\(Self.now())"
        let base = working
        edit { p in
            var next = p
            next.defects.append(Defect(id: id, roomId: roomId, item: item, itemLabel: itemLabel.trimmingCharacters(in: .whitespacesAndNewlines)))
            return next
        }
        defectShell = base.map { (id, $0) }
        editingDefectId = id
    }

    /// A finding about a supplied object rather than a surface of the flat.
    func openObjectDefect(_ objectId: String) {
        if contentLocked { return }
        let id = "d\(Self.now())"
        let base = working
        edit { p in
            var next = p
            next.defects.append(Defect(id: id, objectId: objectId))
            return next
        }
        defectShell = base.map { (id, $0) }
        editingDefectId = id
    }

    /// Opens a finding. On a finalized record the editor is the reader; nothing it shows moves.
    func editDefect(_ id: String) { editingDefectId = id }

    func updateDefect(_ id: String, _ transform: (Defect) -> Defect) {
        edit { p in
            var next = p
            next.defects = p.defects.map { $0.id == id ? transform($0) : $0 }
            return next
        }
    }

    /// Closing the editor discards the shell it opened with, and only that. A finding can carry
    /// a charge, a deadline, a tenant response or a reservation without a word of description,
    /// and testing emptiness on the description alone threw all of it away with no undo.
    ///
    /// When nothing else moved in between, the record is put back exactly as it stood before the
    /// shell was written: `isCurrent` reads contentRevision, so a pair of edits that cancel used
    /// to turn both parties' signatures stale on a record whose content never moved.
    func closeDefect() {
        guard let id = editingDefectId else { return }
        editingDefectId = nil
        let base = defectShell.flatMap { $0.0 == id ? $0.1 : nil }
        defectShell = nil
        guard let p = working, !p.isFinalized(), !finalizing else { return }
        guard let d = p.defects.first(where: { $0.id == id }), d.isUntouched else { return }
        var without = p
        without.defects = p.defects.filter { $0.id != id }
        var unchanged = false
        if let base {
            var compare = without
            compare.contentRevision = base.contentRevision
            compare.exportedEpochMs = base.exportedEpochMs
            unchanged = compare == base
        }
        working = unchanged ? base : without
        scheduleSave()
    }

    func removeDefect(_ id: String, allowUndo: Bool = true) {
        if contentLocked { return }
        let gone = working?.defects.first { $0.id == id }
        if allowUndo {
            reversibleEdit(.defect, evidenceNames: gone?.photoFiles() ?? []) { p in
                var next = p
                next.defects = p.defects.filter { $0.id != id }
                return next
            }
        } else {
            deletePhotos(gone?.photoFiles() ?? [])
            edit { p in
                var next = p
                next.defects = p.defects.filter { $0.id != id }
                return next
            }
        }
        if editingDefectId == id { editingDefectId = nil }
    }

    func deletePhotos(_ names: [String]) {
        guard let dir = photoDir() else { return }
        for name in names.distinct().filter(EvidenceNames.isSafe) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

}
