import Foundation

public enum CompletionRules {
    public static func requiredRecordRoles(_ record: HandoverProtocol, fallbackRole: Role?) -> [Role] {
        var roles: [Role] = []
        let side = record.sessionRole ?? fallbackRole
        // A one-sided record with no side known falls back to both, because the Sign step draws a
        // row per required role: an empty list left the gate demanding a signature it never showed.
        if record.oneSided, let side {
            roles.append(side)
        } else {
            roles.append(.tenant)
            roles.append(.landlord)
        }
        if record.parties.contains(where: { $0.role == .witness }) { roles.append(.witness) }
        if record.parties.contains(where: { $0.role == .expert }) { roles.append(.expert) }
        return roles.distinct()
    }

    /// The key outcome a record needs before it can be frozen. Shared with the dossier's own
    /// section chip, which used to report the card complete on the pill alone and so sat ticked
    /// beside a blocked FINALIZE with nothing on screen naming the missing count.
    public static func keyOutcomeRecorded(_ record: HandoverProtocol) -> Bool {
        // A key count is a number of keys, not a collection, whatever the lint rule reads into its name.
        // swiftlint:disable:next empty_count
        if record.keys.contains(where: { $0.count < 0 }) || record.rooms.contains(where: { $0.keysCount < 0 }) { return false }
        let physical = record.keys.reduce(0) { $0 + $1.count } + record.rooms.reduce(0) { $0 + $1.keysCount }
        switch record.keyTransfer {
        case .notRecorded: return false
        case .allTransferred: return physical > 0
        case .noPhysicalKeys: return physical == 0 && !record.selfMadeKeys
        case .incomplete: return !record.keyTransferNote.isBlank
        }
    }

    public static func protocolCompletionIssues(
        _ record: HandoverProtocol,
        requiredRoles: [Role],
        photoDir: URL,
        signatureDir: URL
    ) -> [FinalizationIssue] {
        var issues: [FinalizationIssue] = []
        if record.address.isBlank { issues.append(.address) }
        if record.place.isBlank { issues.append(.place) }
        if record.objectCanton == nil { issues.append(.canton) }
        if record.handoverDate.isBlank { issues.append(.handoverDate) }
        if record.handoverTime.isBlank { issues.append(.handoverTime) }
        if let overlay = record.resolvedLegalOverlay(), !overlay.isComplete(record.legalOverlay) {
            issues.append(.legalOverlay)
        }
        if [Role.tenant, .landlord].contains(where: { role in record.parties.first { $0.role == role }?.name.isBlank ?? true }) {
            issues.append(.parties)
        }
        // Two different states with two different answers: an empty inspection needs a room added,
        // and a populated one needs its rooms confirmed. One message covered both and told a record
        // with no rooms at all to "confirm every listed room was inspected".
        if record.rooms.isEmpty {
            issues.append(.noRooms)
        } else if record.rooms.contains(where: { !$0.inspected }) {
            issues.append(.rooms)
        }
        if record.objects.contains(where: { !$0.inspected }) { issues.append(.objects) }

        let cards = record.dossierCards()
        let depositIncomplete: Bool
        switch record.deposit.kind {
        case .none: depositIncomplete = true
        case .bankAccount:
            depositIncomplete = record.deposit.amountChf.isBlank || record.deposit.bank.isBlank || record.deposit.account.isBlank
        case .insurance:
            depositIncomplete = record.deposit.amountChf.isBlank || record.deposit.provider.isBlank || record.deposit.policyNo.isBlank
        }
        let emptyAddedComponent =
            (cards.contains(.contract) && record.contract == Contract()) ||
            (cards.contains(.deposit) && depositIncomplete) ||
            (cards.contains(.meters) && record.meters == Meters()) ||
            (cards.contains(.notes) && record.remarks.isBlank && record.chargesStatementBy.isBlank)
        if emptyAddedComponent { issues.append(.dossier) }

        // Gated on the card like every other component above it: removing the Keys card takes the
        // only control that can record an outcome off the screen, and an ungated rule then blocked
        // finalization forever with nothing left anywhere to answer it.
        if cards.contains(.keys), !keyOutcomeRecorded(record) { issues.append(.keys) }
        if record.oneSided, record.unilateralReason == nil { issues.append(.unilateralReason) }
        if record.defects.contains(where: { $0.text.isBlank }) { issues.append(.defectText) }
        if !ProtocolIntegrity.missingEvidence(record, photoDir: photoDir, signatureDir: signatureDir).isEmpty {
            issues.append(.evidence)
        }
        let outcomeMissing = requiredRoles.contains { role in
            !record.signatures.contains { signature in
                signature.role == role && signature.plane == .record && record.isCurrent(signature) &&
                    (signature.refused || !signature.file.isBlank)
            }
        }
        if outcomeMissing { issues.append(.recordOutcomes) }
        return issues
    }
}
