import Foundation

/// The photo annex as people read it at a handover: the photographs gathered into the rooms they
/// were taken in, in walkthrough order, each with what it shows. A card met on a page of its own
/// still says which room it belongs to and what it documents, so nobody has to turn back to the
/// findings to know what they are looking at.
///
/// Text and order only, tested without a graphics context; `PdfExport` lays it out and the HTML
/// copy follows. The Android app's `AnnexContent` is the specification, card for card.
public enum AnnexContent {
    /// A room, the supplied objects without one, the findings whose room is gone, or the meters.
    /// `key` is the room's id, or the group's name, so the body can cite the page the section
    /// opens on even when two rooms share a name.
    public struct Section: Hashable, Sendable {
        public let title: String
        public let cards: [Card]
        public let key: String
    }

    /// One photograph and its legend. `number` is the finding it documents, as numbered in the
    /// body of the record; `where` repeats the section, for a card read on its own.
    public struct Card: Hashable, Sendable {
        public let file: String
        public let `where`: String
        public let number: Int?
        public let title: String
        public let context: [String]
        public let meta: [String]
    }

    /// Captures are stamped in the zone the handovers happen in, whatever the phone's own zone,
    /// so the same photograph reads the same time on both parties' copies.
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter
    }()

    public static func sections(_ p: HandoverProtocol, _ s: Str) -> [Section] {
        var evidence: [String: PhotoEvidence] = [:]
        for item in p.allPhotoEvidence() where evidence[item.file] == nil { evidence[item.file] = item }
        var placed = Set<String>()
        var sections: [Section] = []
        func roomName(_ room: Room) -> String { room.name.ifBlank(s.room(room.kind)) }

        /// The cards for one owner's photographs, numbered within that owner.
        func cards(_ files: [String], _ location: String, _ number: Int?, _ title: String, _ context: [String]) -> [Card] {
            let fresh = files.filter { !$0.isBlank && !placed.contains($0) }
            return fresh.enumerated().map { index, file in
                placed.insert(file)
                return Card(file: file, where: location, number: number, title: title, context: context.filter { !$0.isBlank },
                            meta: meta(file, index, fresh.count, evidence[file], s))
            }
        }
        func finding(_ index: Int, _ location: String) -> [Card] {
            let d = p.defects[index]
            var context: [String] = []
            if let item = p.defectItemLabel(d, s) { context.append(item) }
            if d.chargedToTenant { context.append(s.chargedToTenant) }
            switch d.fixBy {
            case .tenant: context.append("\(s.fixByLabel): \(s.role(.tenant))")
            case .landlord: context.append("\(s.fixByLabel): \(s.role(.landlord))")
            case .open: break
            }
            if d.tenantResponse != .notStated { context.append("\(s.tenantResponseLabel): \(s.tenantResponse(d.tenantResponse))") }
            return cards(d.photoFiles(), location, index + 1, d.text.ifBlank("–"), context)
        }
        func objectCards(_ entry: ObjectEntry, _ location: String) -> [Card] {
            let name = entry.displayName(s)
            let own = cards(entry.photoFiles(), location, nil, name, [entry.note])
            let findings = p.defects.indices.filter { p.defects[$0].objectId == entry.id }.flatMap { finding($0, "\(location) · \(name)") }
            return own + findings
        }

        for room in p.rooms {
            let name = roomName(room)
            let roomCards = cards((p.details.roomPhotos[room.id] ?? []).map(\.file), name, nil, s.overviewPhotos, []) +
                Report.roomFindings(p, room.id).flatMap { finding($0.number - 1, name) } +
                p.objects.filter { $0.roomId == room.id }.flatMap { objectCards($0, name) }
            if !roomCards.isEmpty { sections.append(Section(title: name, cards: roomCards, key: room.id)) }
        }
        let roomless = p.objects.filter { entry in !p.rooms.contains { $0.id == entry.roomId } }.flatMap { objectCards($0, s.objects) } +
            p.defects.indices.filter { i in !p.defects[i].objectId.isBlank && !p.objects.contains { $0.id == p.defects[i].objectId } }
                .flatMap { finding($0, s.objects) }
        if !roomless.isEmpty { sections.append(Section(title: s.objects, cards: roomless, key: "objects")) }
        let orphaned = Report.orphanedFindings(p).flatMap { finding($0.number - 1, s.defects) }
        if !orphaned.isEmpty { sections.append(Section(title: s.defects, cards: orphaned, key: "defects")) }
        let meters = p.details.readings.flatMap { r -> [Card] in
            let reading = [r.value, r.unit].filter { !$0.isBlank }.joined(separator: " ")
            let taken = [SwissDate.display(r.date), r.time].filter { !$0.isBlank }.joined(separator: " ")
            return cards(r.photos.map(\.file), s.meters, nil, [r.label, r.identifier].filter { !$0.isBlank }.joined(separator: " · "),
                         [reading.isBlank ? "" : "\(s.reading): \(reading)", taken, r.note])
        }
        if !meters.isEmpty { sections.append(Section(title: s.meters, cards: meters, key: "meters")) }
        // Nothing the annex is asked to print may go missing because no section claimed it.
        let rest = Report.plates(p).map(\.file).filter { !placed.contains($0) }
        if !rest.isEmpty { sections.append(Section(title: s.photos, cards: cards(rest, s.photos, nil, s.photos, []), key: "photos")) }
        return sections
    }

    /// Which photograph of how many, when it was taken or imported, and its file.
    private static func meta(_ file: String, _ index: Int, _ count: Int, _ evidence: PhotoEvidence?, _ s: Str) -> [String] {
        var lines = ["\(s.photo) \(index + 1) / \(count)"]
        if let evidence {
            let imported = evidence.source == .gallery
            // Each time falls back to the other when its own is zero, and the line is left out
            // when both are.
            let own = imported ? evidence.importedEpochMs : evidence.capturedEpochMs
            let other = imported ? evidence.capturedEpochMs : evidence.importedEpochMs
            let epoch = own > 0 ? own : other
            if epoch > 0 {
                lines.append("\(imported ? s.importedOn : s.capturedOn) \(stamp.string(from: Date(timeIntervalSince1970: Double(epoch) / 1000)))")
            }
        }
        lines.append(file)
        return lines
    }
}
