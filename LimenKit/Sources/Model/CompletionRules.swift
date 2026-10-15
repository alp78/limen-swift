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

    public static func requiredRecordParticipants(_ record: HandoverProtocol, fallbackRole: Role? = nil) -> [Party] {
        let roles = requiredRecordRoles(record, fallbackRole: fallbackRole)
        return record.parties.filter { roles.contains($0.role) }
    }

    public static func keyOutcomeRecorded(_ record: HandoverProtocol) -> Bool {
        let devices = record.details.accessDevices
        // Physical counts are numbers, not collections.
        // swiftlint:disable:next empty_count
        if record.keys.contains(where: { $0.count < 0 }) || record.rooms.contains(where: { $0.keysCount < 0 }) ||
            devices.contains(where: { $0.expected < 0 || $0.transferred < 0 || $0.label.isBlank || ($0.expected != $0.transferred && $0.note.isBlank) }) { return false }
        // Add with overflow reporting because archives can contain hostile counts.
        var physical = 0
        for count in record.keys.map(\.count) + record.rooms.map(\.keysCount) + devices.map(\.transferred) {
            let sum = physical.addingReportingOverflow(count)
            if sum.overflow { return false }
            physical = sum.partialValue
        }
        switch record.keyTransfer {
        case .notRecorded: return false
        case .allTransferred: return physical > 0 && devices.allSatisfy { $0.expected == $0.transferred }
        case .noPhysicalKeys: return physical == 0 && !record.selfMadeKeys && devices.allSatisfy { $0.expected == 0 }
        case .incomplete: return !record.keyTransferNote.isBlank
        }
    }

    public static func depositRecorded(_ record: HandoverProtocol) -> Bool {
        if !(record.details.scopeNotes["Deposit"] ?? "").isBlank { return true }
        switch record.deposit.kind {
        case .none: return true
        case .unknown: return false
        case .bankAccount: return !record.deposit.amountChf.isBlank && !record.deposit.bank.isBlank && !record.deposit.account.isBlank
        case .insurance: return !record.deposit.amountChf.isBlank && !record.deposit.provider.isBlank && !record.deposit.policyNo.isBlank
        }
    }

    public static func incompleteDossierTarget(_ record: HandoverProtocol) -> String {
        let dates = [record.contract.conclusionDate, record.contract.startDate, record.contract.endDate, record.contract.noticeDate]
        let amounts = [record.contract.monthlyRentChf, record.contract.serviceChargesChf]
        if RecordInputValidation.invalidOptionalDate(record.details.actualTransferDate) || invalidNotification(record) { return "transfer" }
        if dates.contains(where: RecordInputValidation.invalidOptionalDate) || amounts.contains(where: invalidAmount) ||
            record.carries(.contract) && record.contract == Contract() && !hasScope(record, "Contract") { return "card-Contract" }
        if record.carries(.deposit) && !depositRecorded(record) || invalidAmount(record.deposit.amountChf) { return "card-Deposit" }
        if record.details.attachments.contains(where: { $0.title.isBlank || $0.file.isBlank && $0.externalReference.isBlank }) { return "documents" }
        if record.details.followUps.contains(where: { $0.description.isBlank || [$0.discoveredDate, $0.notifiedDate, $0.deadline].contains(where: RecordInputValidation.invalidOptionalDate) }) { return "follow-up" }
        if record.details.readings.contains(where: invalidReading) { return "readings" }
        if record.carries(.meters) && record.meters.isBlank && record.details.readings.isEmpty && !hasScope(record, "Meters") { return "card-Meters" }
        return "card-Notes"
    }

    private static func hasScope(_ record: HandoverProtocol, _ key: String) -> Bool { !(record.details.scopeNotes[key] ?? "").isBlank }
    private static func invalidAmount(_ value: String) -> Bool { !value.isBlank && NumberValidation.nonNegativeNumber(value) == nil }
    private static func invalidReading(_ reading: MeterReading) -> Bool {
        reading.label.isBlank || RecordInputValidation.invalidOptionalDate(reading.date) ||
            ((reading.value.isBlank || reading.unit.isBlank || reading.identifier.isBlank) && reading.note.isBlank) || invalidAmount(reading.value)
    }
    private static func invalidNotification(_ record: HandoverProtocol) -> Bool {
        !record.details.notificationDays.isBlank &&
            (!(Int(record.details.notificationDays).map { (1...365).contains($0) } ?? false) || record.details.notificationClause.isBlank)
    }

    public static func protocolCompletionIssues(_ record: HandoverProtocol, requiredRoles: [Role], photoDir: URL, signatureDir: URL) -> [FinalizationIssue] {
        var issues: [FinalizationIssue] = []
        if record.address.isBlank { issues.append(.address) }
        if record.place.isBlank { issues.append(.place) }
        if record.objectCanton == nil { issues.append(.canton) }
        if SwissDate.parse(record.handoverDate) == nil { issues.append(.handoverDate) }
        if !RecordInputValidation.validTime(record.handoverTime) { issues.append(.handoverTime) }
        if let overlay = record.resolvedLegalOverlay(), !overlay.isComplete(record.legalOverlay) { issues.append(.legalOverlay) }
        if record.details.legalSnapshot != nil && record.resolvedLegalOverlay() == nil { issues.append(.legalOverlay) }
        if [Role.tenant, .landlord].contains(where: { role in !record.parties.contains { $0.role == role && !$0.name.isBlank } }) ||
            record.parties.contains(where: { $0.name.isBlank || !$0.representedBy.isBlank && $0.authority.isBlank }) ||
            Set(record.parties.map { $0.participantKey() }).count != record.parties.count { issues.append(.parties) }
        if record.rooms.isEmpty && !hasScope(record, "Inspection") { issues.append(.noRooms) } else if record.rooms.contains(where: { !$0.inspected && !hasScope(record, $0.id) }) { issues.append(.rooms) }
        if record.objects.contains(where: { !$0.inspected && !hasScope(record, $0.id) }) { issues.append(.objects) }
        let optionalDates = [record.contract.conclusionDate, record.contract.startDate, record.contract.endDate, record.contract.noticeDate,
                             record.chargesStatementBy, record.details.actualTransferDate] + record.defects.map(\.fixDeadline) +
            record.details.readings.map(\.date) + record.details.followUps.flatMap { [$0.discoveredDate, $0.notifiedDate, $0.deadline] } +
            record.details.estimates.entries.map { $0.value.date }
        if optionalDates.contains(where: RecordInputValidation.invalidOptionalDate) { issues.append(.dossier) }
        let emptyComponent = record.carries(.contract) && record.contract == Contract() && !hasScope(record, "Contract") ||
            record.carries(.deposit) && !depositRecorded(record) ||
            record.carries(.meters) && record.meters.isBlank && record.details.readings.isEmpty && !hasScope(record, "Meters") ||
            record.carries(.notes) && record.remarks.isBlank && record.chargesStatementBy.isBlank && !hasScope(record, "Notes")
        if emptyComponent || record.details.readings.contains(where: invalidReading) ||
            record.details.attachments.contains(where: { $0.title.isBlank || $0.file.isBlank && $0.externalReference.isBlank }) ||
            record.details.followUps.contains(where: { $0.description.isBlank }) ||
            [record.contract.monthlyRentChf, record.contract.serviceChargesChf, record.deposit.amountChf].contains(where: invalidAmount) ||
            record.details.estimates.entries.contains(where: { !$0.value.isValid }) || invalidNotification(record) { issues.append(.dossier) }
        if record.carries(.keys) ? !keyOutcomeRecorded(record) : !hasScope(record, "Keys") { issues.append(.keys) }
        if !record.details.actualTransferTime.isBlank && !RecordInputValidation.validTime(record.details.actualTransferTime) ||
            record.details.readings.contains(where: { !$0.time.isBlank && !RecordInputValidation.validTime($0.time) }) { issues.append(.handoverTime) }
        if record.oneSided && (record.unilateralReason == nil || record.unilateralReason == .other && record.unilateralNote.isBlank) { issues.append(.unilateralReason) }
        if record.defects.contains(where: { $0.text.isBlank }) { issues.append(.defectText) }
        if !ProtocolIntegrity.missingEvidence(record, photoDir: photoDir, signatureDir: signatureDir).isEmpty { issues.append(.evidence) }
        if requiredRoles.contains(where: { role in !record.parties.contains { $0.role == role } }) ||
            record.parties.filter({ requiredRoles.contains($0.role) }).contains(where: { party in
                guard let signature = record.signatureFor(party: party), record.isCurrent(signature) else { return true }
                return !(signature.refused || !signature.file.isBlank || ["absent", "unable"].contains(signature.outcome)) ||
                    !signature.outcome.isBlank && signature.reservation.isBlank
            }) { issues.append(.recordOutcomes) }
        return issues.distinct()
    }
}
