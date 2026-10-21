import Foundation

/// Supplemental content is selected once for the preview, PDF and accessible companion. Since
/// Android 1.2.6 no line joins independent facts with a middle dot: each fact is its own line,
/// a label takes a colon, and a role follows a name in parentheses.
public enum RecordContent {
    public struct Section: Hashable, Sendable {
        public let title: String
        public let paragraphs: [String]
    }

    public static func extraContent(record p: HandoverProtocol, strings s: Str) -> [Section] {
        let d = p.details
        var sections: [Section] = []
        func section(_ title: String, _ paragraphs: [String]) {
            let values = paragraphs.filter { !$0.isBlank }
            if !values.isEmpty { sections.append(Section(title: title, paragraphs: values)) }
        }
        section(s.actualTransfer, [
            d.actualTransferDate.isBlank ? d.actualTransferTime : "\(SwissDate.display(d.actualTransferDate)) \(d.actualTransferTime)",
            d.notificationClause.isBlank ? "" : "\(s.notificationClause): \(d.notificationClause)\n\(d.notificationDays)"
        ])
        // Only when a language was recorded, as Android prints it; the translation notice travels
        // under it, since the labels of this document are translated and the statements are not.
        section(s.understoodLanguage, d.understoodLanguage.isBlank ? [] : [d.understoodLanguage, s.translationNotice])
        section(s.scopeReason, d.scopeNotes.entries.map { key, reason in
            let label = p.rooms.first { $0.id == key }.map { $0.name.ifBlank(s.room($0.kind)) } ??
                p.objects.first { $0.id == key }.map { $0.displayName(s) } ??
                DossierCard(rawValue: key).map { s.dossierCard($0) } ?? (key == "Inspection" ? s.stepInspection : key)
            return "\(label): \(reason)"
        })
        section(s.meters, d.readings.map { "\($0.label)\n\(s.identifier): \($0.identifier)\n\(s.reading): \($0.value) \($0.unit)\n\(SwissDate.display($0.date)) \($0.time)\n\($0.note)" })
        section(s.accessDevices, d.accessDevices.map { "\($0.label)\n\($0.identifier)\n\(s.expected): \($0.expected)\n\(s.transferred): \($0.transferred)\n\($0.note)" })
        // One fact per line per document, as Android prints them: no hash, which tells the people
        // at a handover nothing, and no MIME type or import time, which the evidence check reads
        // from the record itself.
        section(s.attachments, d.attachments.map { "\(s.documentKind($0.kind)): \($0.title)\n\($0.externalReference)\n\($0.file)\n\($0.bytes) B" })
        // No list of photographs here: each one carries its file name and capture time in the
        // annex, in its frame, beside the picture it describes.
        section(s.followUps, d.followUps.map { "\($0.description)\n\(s.discoveredOn): \(SwissDate.display($0.discoveredDate))\n\(s.notifiedOn): \(SwissDate.display($0.notifiedDate))\n\($0.recipient)\n\($0.method)\n\(s.fixDeadline): \(SwissDate.display($0.deadline))\n\($0.done ? s.done : s.toVerify)" })
        section(s.faceValue, d.estimates.entries.map { id, e in
            let number = p.defects.firstIndex { $0.id == id }.map { String($0 + 1) } ?? id
            return "\(s.defects) \(number): \(e.basis)\n\(s.repairCost): \(e.replacementChf)\n\(s.ageYears): \(e.ageYears)\n\(s.lifespanYears): \(e.lifeYears)\n\(e.date)\n\(e.source)\n\(s.estimateNotice)"
        })
        section(s.reservationLabel, p.parties.compactMap { party in
            let note = p.reservationFor(party: party)
            return note.isBlank ? nil : "\(party.signerName()) (\(s.role(party.role))): \(note)"
        })
        var legal: [String] = []
        if !d.municipality.isBlank { legal.append("\(s.municipality): \(d.municipality)\n\(s.habitableRooms): \(d.habitableRooms)") } else if !d.habitableRooms.isBlank { legal.append("\(s.habitableRooms): \(d.habitableRooms)") }
        if !d.district.isBlank { legal.append("\(s.district): \(d.district)") }
        if p.legalOverlay.checks[.cantonalDepositHandling] != nil { legal.append(s.depositLocal(p.objectCanton)) }
        if p.objectCanton == .ti { legal.append(s.ticinoExpertRoute) }
        if let snapshot = d.legalSnapshot ?? (p.isFinalized() ? nil : p.freezeLegalRules()) {
            legal += ["\(snapshot.ruleSetId)\n\(snapshot.checkedOn)"] + snapshot.sources
        }
        section(s.legalOverlayTitle, legal)
        return sections
    }
}

extension Str {
    public func documentKind(_ kind: DocumentKind) -> String {
        switch kind {
        case .lease: return contract
        case .rentForm: return initialRentForm
        case .mandate: return authority
        case .priorReport: return lastProtocol
        case .deposit: return deposit
        case .delivery: return copyDelivery
        case .other:
            switch lang {
            case .en: return "Other document"
            case .fr: return "Autre document"
            case .de: return "Andere Beilage"
            case .it: return "Altro documento"
            case .rm: return "Auter document"
            }
        }
    }
}

extension Str {
    /// Android ui/LegalOverlayPanel.kt, retained verbatim in all five languages.
    public var ticinoExpertRoute: String {
        switch lang {
        case .en: return "In Ticino, parties or the conciliation authority may request the municipal property expert. This is an available procedure, not a mandatory visit for every handover."
        case .fr: return "Au Tessin, les parties ou l’autorité de conciliation peuvent solliciter l’expert communal immobilier. Cette procédure est disponible, sans visite obligatoire pour chaque remise."
        case .de: return "Im Tessin können die Parteien oder die Schlichtungsbehörde die kommunale Immobilienfachperson beiziehen. Dies ist keine Pflichtbesichtigung bei jeder Übergabe."
        case .it: return "In Ticino le parti o l’autorità di conciliazione possono richiedere l’intervento del perito comunale degli immobili. Non è una visita obbligatoria per ogni consegna."
        case .rm: return "En il Tessin pon las partidas u l’autoritad da mediaziun dumandar il perit communal d’immobiglias. Quai n’è betg ina visita obligatorica per mintga surdada."
        }
    }
}
