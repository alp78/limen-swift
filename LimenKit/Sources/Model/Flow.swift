import Foundation

/// The protocol flow opens from the case and owns the screen until it is closed. It is restored
/// after a process death because the camera app can interrupt a handover mid-walk.
///
/// Not a stepper. A handover is walked in the order the flat is built, not the order an app
/// imagines, so `hub` is the home everything returns to and nothing is gated behind anything
/// else. `sign` and `export` are the exception: they follow `review` because a signature that saw
/// no review is worth nothing.
public enum FlowStep: String, CaseIterable, Hashable, Sendable {
    case hub = "Hub"
    case inspection = "Inspection"
    case objects = "Objects"
    case dossier = "Dossier"
    case review = "Review"
    case sign = "Sign"
    case export = "Export"

    /// Where back goes from here. Nil leaves the flow entirely.
    public var parent: FlowStep? {
        switch self {
        case .hub: return nil
        case .inspection, .objects, .dossier, .review: return .hub
        case .sign: return .review
        case .export: return .sign
        }
    }

    public var ordinal: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// What still prevents a protocol from becoming the frozen record both parties reviewed.
public enum FinalizationIssue: String, CaseIterable, Hashable, Sendable {
    case address, place, canton, handoverDate, handoverTime, legalOverlay, parties, noRooms, rooms
    case objects, dossier, keys, unilateralReason, defectText, evidence, recordOutcomes
}

/// Why an export is withheld, rather than silently producing a misleading document.
public enum ExportIssue: String, CaseIterable, Hashable, Sendable {
    case notFinalized, integrityMismatch, failed
}

public enum UndoKind: String, CaseIterable, Hashable, Sendable {
    case defect, photo, object, keyCounts
    // The dossier's entries, offered back since Android 1.2.7: each holds text typed by hand and
    // its delete key sits among the photograph keys.
    case reading, accessDevice, document, followUp, estimate, party, keyKind
}

/// What an info mark explains: a lead sentence, then bullets, never a wall of text. The house rule
/// for this app: explanations live behind the mark, structured, and no small print ever sits
/// inline on a screen.
public struct Tip: Hashable, Sendable {
    public let lead: String
    public let bullets: [String]

    public init(lead: String, bullets: [String] = []) {
        self.lead = lead
        self.bullets = bullets
    }
}
