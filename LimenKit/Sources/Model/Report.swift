import Foundation

/// What the exported document will contain, chosen before anything is drawn.
///
/// Kept apart from `PdfExport` because that file cannot be tested without a graphics context.
/// The decisions worth verifying are all here, and none of them touch a canvas.
///
/// The numbering is the contract between the body and the photo annex. A finding is numbered by
/// its position in the whole record rather than within its room, so the number under a
/// photograph names exactly one finding on exactly one page. Renumber here and the annex
/// captions lie.
public enum Report {
    /// A finding with the number it prints under.
    public struct Numbered: Hashable, Sendable {
        public let number: Int
        public let defect: Defect
    }

    /// A photograph and what it belongs to, so the annex can be read on its own.
    public struct Plate: Hashable, Sendable {
        public let file: String
        public let sha256: String
        public let owner: PlateOwner
    }

    public enum PlateOwner: Hashable, Sendable {
        /// A finding, cited by the number it prints under in the body.
        case finding(Int)
        /// A supplied object, cited by name, because an object has no number to cite.
        case supplied(ObjectEntry)
    }

    /// This room's findings, and nothing else.
    ///
    /// A room contributes exactly its defects here. Its separate inspected flag is what lets the
    /// PDF distinguish an explicitly clean room from one that was never checked.
    public static func roomFindings(_ p: HandoverProtocol, _ roomId: String) -> [Numbered] {
        p.defects.enumerated()
            .filter { $0.element.objectId.isBlank && $0.element.roomId == roomId }
            .map { Numbered(number: $0.offset + 1, defect: $0.element) }
    }

    /// Findings about a supplied object rather than a surface of the flat.
    public static func objectFindings(_ p: HandoverProtocol) -> [Numbered] {
        p.defects.enumerated()
            .filter { !$0.element.objectId.isBlank }
            .map { Numbered(number: $0.offset + 1, defect: $0.element) }
    }

    /// Findings whose room is gone.
    ///
    /// Removing a room takes its findings with it, so this is normally empty. It exists because a
    /// record that lost a room some other way would otherwise print a heading count and an annex
    /// caption for a finding that appears on no page.
    public static func orphanedFindings(_ p: HandoverProtocol) -> [Numbered] {
        p.defects.enumerated()
            .filter { pair in pair.element.objectId.isBlank && !p.rooms.contains { $0.id == pair.element.roomId } }
            .map { Numbered(number: $0.offset + 1, defect: $0.element) }
    }

    /// Every photograph on the record, findings first and then the supplied objects.
    public static func plates(_ p: HandoverProtocol) -> [Plate] {
        var plates: [Plate] = []
        for (index, d) in p.defects.enumerated() {
            for name in d.photoFiles() {
                let hash = d.photoEvidence.first { $0.file == name }?.sha256 ?? ""
                plates.append(Plate(file: name, sha256: hash, owner: .finding(index + 1)))
            }
        }
        for entry in p.objects {
            for name in entry.photoFiles() {
                let hash = entry.photoEvidence.first { $0.file == name }?.sha256 ?? ""
                plates.append(Plate(file: name, sha256: hash, owner: .supplied(entry)))
            }
        }
        return plates
    }
}
