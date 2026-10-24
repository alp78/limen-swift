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

    public static func invalidDate(_ value: String) -> Bool { RecordInputValidation.invalidOptionalDate(value) }

    public static func invalidTime(_ value: String) -> Bool { !value.isBlank && !RecordInputValidation.validTime(value) }

    public static func invalidAmount(_ value: String) -> Bool { !value.isBlank && NumberValidation.nonNegativeNumber(value) == nil }

    /// The deposit amount as the Deposit card shows it. Only the two kinds that print an amount
    /// have a field for it, and the pill leaves the typed text behind when it moves to None or
    /// Unknown: the gate used to read that text and block finalization over a value nobody could
    /// reach to correct.
    public static func depositAmountShown(_ record: HandoverProtocol) -> String {
        record.deposit.kind == .bankAccount || record.deposit.kind == .insurance ? record.deposit.amountChf : ""
    }

    // The rows the gate rejects, one definition each: the gate, the dossier chips and the messages
    // that name the cause all ask these, so none of them can accept what another refuses.
    public static func readingFaulty(_ r: MeterReading) -> Bool {
        r.label.isBlank || invalidDate(r.date) || ((r.value.isBlank || r.unit.isBlank || r.identifier.isBlank) && r.note.isBlank)
    }

    public static func attachmentFaulty(_ a: SupportingDocument) -> Bool { a.title.isBlank || (a.file.isBlank && a.externalReference.isBlank) }

    public static func followUpFaulty(_ f: FollowUp) -> Bool {
        f.description.isBlank || [f.discoveredDate, f.notifiedDate, f.deadline].contains(where: invalidDate)
    }

    /// The estimate's date is gated here too, which Android does not do: the field keeps a
    /// half-typed date verbatim and the paper prints it as typed.
    public static func estimateFaulty(_ e: ReplacementEstimate) -> Bool {
        NumberValidation.nonNegativeNumber(e.replacementChf) == nil || NumberValidation.nonNegativeNumber(e.ageYears) == nil ||
            (NumberValidation.nonNegativeNumber(e.lifeYears) ?? 0) <= 0 || invalidDate(e.date)
    }

    public static func notificationFaulty(_ d: RecordDetails) -> Bool {
        !d.notificationDays.isBlank && (!(Int(d.notificationDays).map { (1...365).contains($0) } ?? false) || d.notificationClause.isBlank)
    }

    public static func contractFilled(_ record: HandoverProtocol) -> Bool { record.contract != Contract() || hasScope(record, "Contract") }

    public static func contractValid(_ record: HandoverProtocol) -> Bool {
        ![record.contract.conclusionDate, record.contract.startDate, record.contract.endDate, record.contract.noticeDate].contains(where: invalidDate) &&
            ![record.contract.monthlyRentChf, record.contract.serviceChargesChf].contains(where: invalidAmount)
    }

    public static func metersFilled(_ record: HandoverProtocol) -> Bool {
        !record.meters.isBlank || !record.details.readings.isEmpty || hasScope(record, "Meters")
    }

    public static func notesFilled(_ record: HandoverProtocol) -> Bool { !record.remarks.isBlank || !record.chargesStatementBy.isBlank }

    public static func transferValid(_ d: RecordDetails) -> Bool { !invalidDate(d.actualTransferDate) && !notificationFaulty(d) }

    // The ticks on the dossier's section chips. A section ticks only when it holds something and
    // the gate has nothing to say about it, so a ticked chip cannot sit beside a blocked FINALIZE.
    public static func objectRecorded(_ record: HandoverProtocol) -> Bool {
        !record.address.isBlank && !record.place.isBlank && record.objectCanton != nil &&
            SwissDate.parse(record.handoverDate) != nil && !record.handoverTime.isBlank && !invalidTime(record.handoverTime) &&
            !invalidDate(record.lastProtocolDate) && record.resolvedLegalOverlay()?.isComplete(record.legalOverlay) == true
    }

    public static func partiesRecorded(_ record: HandoverProtocol) -> Bool {
        [Role.tenant, .landlord].allSatisfy { role in record.parties.contains { $0.role == role && !$0.name.isBlank } } &&
            !record.parties.contains(where: { $0.name.isBlank || (!$0.representedBy.isBlank && $0.authority.isBlank) }) &&
            Set(record.parties.map { $0.participantKey() }).count == record.parties.count
    }

    public static func dossierCardRecorded(_ record: HandoverProtocol, _ card: DossierCard) -> Bool {
        switch card {
        case .contract: return contractFilled(record) && contractValid(record)
        case .deposit: return depositRecorded(record) && !invalidAmount(depositAmountShown(record))
        case .meters: return metersFilled(record) && !record.details.readings.contains(where: { readingFaulty($0) || invalidTime($0.time) })
        case .keys: return keyOutcomeRecorded(record)
        case .notes: return notesFilled(record) && !invalidDate(record.chargesStatementBy)
        }
    }

    public static func transferRecorded(_ record: HandoverProtocol) -> Bool {
        !record.details.actualTransferDate.isBlank && transferValid(record.details) && !invalidTime(record.details.actualTransferTime)
    }

    public static func attachmentsRecorded(_ record: HandoverProtocol) -> Bool {
        !record.details.attachments.isEmpty && !record.details.attachments.contains(where: attachmentFaulty)
    }

    public static func followUpsRecorded(_ record: HandoverProtocol) -> Bool {
        !record.details.followUps.isEmpty && !record.details.followUps.contains(where: followUpFaulty)
    }

    /// The first dossier section to correct, shared by actionable completion messages. The
    /// readings have a panel of their own here, where Android's sit under the Meters card.
    public static func incompleteDossierTarget(_ record: HandoverProtocol) -> String {
        if invalidDate(record.lastProtocolDate) { return "object" }
        if !transferValid(record.details) { return "transfer" }
        if !contractValid(record) || record.carries(.contract) && !contractFilled(record) { return "card-Contract" }
        // On the card, as the gate asks it: a deposit kind left unknown in a record without the
        // card is data no screen writes, and there would be no card to scroll to.
        if record.carries(.deposit) && !depositRecorded(record) || invalidAmount(depositAmountShown(record)) { return "card-Deposit" }
        if record.details.attachments.contains(where: attachmentFaulty) { return "documents" }
        if record.details.followUps.contains(where: followUpFaulty) { return "follow-up" }
        if record.details.readings.contains(where: readingFaulty) { return "readings" }
        if record.carries(.meters) && !metersFilled(record) { return "card-Meters" }
        return "card-Notes"
    }

    /// Each value the dossier check rejected, by the name it carries on screen. The message used
    /// to list Deposit, Meters and Attachments whenever they existed, which sent a person to three
    /// sections that were fine while the cause sat in a rent, a wear estimate or a follow-up.
    public static func dossierCauses(_ record: HandoverProtocol, _ s: Str) -> [String] {
        var causes: [String] = []
        let cards = record.dossierCards()
        for (name, date) in [(s.leaseConcludedOn, record.contract.conclusionDate), (s.tenancyStart, record.contract.startDate),
                             (s.tenancyEnd, record.contract.endDate), (s.noticeDate, record.contract.noticeDate), (s.chargesBy, record.chargesStatementBy),
                             (s.lastProtocol, record.lastProtocolDate), (s.actualTransfer, record.details.actualTransferDate)] where invalidDate(date) {
            causes.append(name)
        }
        for (name, amount) in [(s.monthlyRent, record.contract.monthlyRentChf), (s.serviceCharges, record.contract.serviceChargesChf),
                               (s.depositAmount, depositAmountShown(record))] where invalidAmount(amount) {
            causes.append(name)
        }
        for d in record.defects where invalidDate(d.fixDeadline) { causes.append("\(s.fixDeadline): \(d.text)") }
        for d in record.defects where record.details.estimates[d.id].map(estimateFaulty) == true { causes.append("\(s.faceValue): \(d.text)") }
        if notificationFaulty(record.details) { causes.append(s.notificationClause) }
        if record.details.readings.contains(where: readingFaulty) { causes.append(s.meters) }
        if record.details.attachments.contains(where: attachmentFaulty) { causes.append(s.attachments) }
        if record.details.followUps.contains(where: followUpFaulty) { causes.append(s.followUps) }
        if cards.contains(.contract), !contractFilled(record) { causes.append(s.contract) }
        if cards.contains(.deposit), !depositRecorded(record) { causes.append(s.deposit) }
        if cards.contains(.meters), !metersFilled(record) { causes.append(s.meters) }
        if cards.contains(.notes), !notesFilled(record) { causes.append(s.notes) }
        return causes.distinct()
    }

    /// The times other than the handover time that the gate rejected, since the message itself names only that one.
    public static func timeCauses(_ record: HandoverProtocol, _ s: Str) -> [String] {
        var causes: [String] = []
        if invalidTime(record.details.actualTransferTime) { causes.append(s.actualTransfer) }
        for r in record.details.readings where invalidTime(r.time) { causes.append(r.label.isBlank ? s.meters : "\(s.meters): \(r.label)") }
        return causes
    }

    private static func hasScope(_ record: HandoverProtocol, _ key: String) -> Bool { !(record.details.scopeNotes[key] ?? "").isBlank }

    public static func protocolCompletionIssues(_ record: HandoverProtocol, requiredRoles: [Role], photoDir: URL, signatureDir: URL) -> [FinalizationIssue] {
        var issues: [FinalizationIssue] = []
        if record.address.isBlank { issues.append(.address) }
        if record.place.isBlank { issues.append(.place) }
        if record.objectCanton == nil { issues.append(.canton) }
        if SwissDate.parse(record.handoverDate) == nil { issues.append(.handoverDate) }
        if !RecordInputValidation.validTime(record.handoverTime) { issues.append(.handoverTime) }
        // Free text a date field keeps verbatim while it is half typed: whatever is not a date
        // would print as typed on the signed record.
        let optionalDates = [record.chargesStatementBy, record.lastProtocolDate] + record.defects.map(\.fixDeadline)
        if optionalDates.contains(where: invalidDate) || !contractValid(record) || !transferValid(record.details) { issues.append(.dossier) }
        if let overlay = record.resolvedLegalOverlay(), !overlay.isComplete(record.legalOverlay) { issues.append(.legalOverlay) }
        if record.details.legalSnapshot != nil && record.resolvedLegalOverlay() == nil { issues.append(.legalOverlay) }
        if !partiesRecorded(record) { issues.append(.parties) }
        // Two different states with two different answers: an empty inspection needs a room added,
        // and a populated one needs its rooms confirmed.
        if record.rooms.isEmpty && !hasScope(record, "Inspection") { issues.append(.noRooms) } else if record.rooms.contains(where: { !$0.inspected && !hasScope(record, $0.id) }) { issues.append(.rooms) }
        if record.objects.contains(where: { !$0.inspected && !hasScope(record, $0.id) }) { issues.append(.objects) }
        let emptyComponent = record.carries(.contract) && !contractFilled(record) ||
            record.carries(.deposit) && !depositRecorded(record) ||
            record.carries(.meters) && !metersFilled(record) ||
            record.carries(.notes) && !notesFilled(record)
        if emptyComponent { issues.append(.dossier) }
        // Gated on the card like every other component above it: removing the Keys card takes the
        // answer with it, and the reason for the removal stands in for the outcome.
        if record.carries(.keys) ? !keyOutcomeRecorded(record) : !hasScope(record, "Keys") { issues.append(.keys) }
        if record.details.readings.contains(where: readingFaulty) || record.details.attachments.contains(where: attachmentFaulty) ||
            record.details.followUps.contains(where: followUpFaulty) { issues.append(.dossier) }
        if invalidAmount(depositAmountShown(record)) { issues.append(.dossier) }
        if record.details.estimates.entries.contains(where: { estimateFaulty($0.value) }) { issues.append(.dossier) }
        if invalidTime(record.details.actualTransferTime) || record.details.readings.contains(where: { invalidTime($0.time) }) { issues.append(.handoverTime) }
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
