import Foundation

/// The dossier panels: the dated canton checks, the data controller, the contract, the deposit,
/// the meters and the keys, each only when the record carries it.
extension PdfExport.Sheet {
    /// The dated canton checks actually recorded, never inferred into an older frozen PDF.
    func legalOverlay(_ p: HandoverProtocol) {
        guard let overlay = p.resolvedLegalOverlay() else { return }
        var blocks: [any PdfExport.Block] = [PdfExport.Fields([(s.cantonLabel, s.canton(overlay.canton)), (s.legalBasis, s.legalProfile(overlay.profile))])]
        if p.kind == .entry { blocks.append(PdfExport.Text("\(s.initialRentForm): \(s.initialRentFormRule(overlay.initialRentFormRule))", .small)) }
        // Only the requirements this record still resolves. Printed from the raw answer map, a
        // deposit set back to None left "Deposit proof: Confirmed" on a record stating there is
        // no deposit, which neither the panel nor the completeness gate would ever have shown.
        for requirement in overlay.requirements.sorted(by: { $0.ordinal < $1.ordinal }) {
            guard let status = p.legalOverlay.status(requirement) else { continue }
            blocks.append(PdfExport.Text("\(s.legalRequirement(requirement)): \(s.legalCheckStatus(status))", .body))
            if let note = p.legalOverlay.notes[requirement], !note.isBlank { blocks.append(PdfExport.Text(note, .small)) }
        }
        if !p.legalOverlay.note.isBlank { blocks.append(PdfExport.Text("\(s.legalOverlayNote): \(p.legalOverlay.note)", .small)) }
        let ruleSet = p.legalOverlay.ruleSetId.isBlank ? "" : " (\(p.legalOverlay.ruleSetId))"
        // Cited per canton: the BWO form is federal, the RULV are Vaud's, and naming them on a
        // Bern or Ticino record stated something untrue about its legal basis.
        blocks.append(PdfExport.Text("\(s.legalSnapshotFor(overlay.canton))\(ruleSet)", .small))
        panel(PdfExport.Panel(s.legalOverlayTitle, blocks))
    }

    func dataController(_ p: HandoverProtocol) {
        let controller = p.controllerIdentity
        if controller.isBlank { return }
        var blocks: [any PdfExport.Block] = []
        if !controller.organisation.isBlank { blocks.append(PdfExport.Text(controller.organisation, .bodyMedium)) }
        if !controller.contactName.isBlank { blocks.append(PdfExport.Text(controller.contactName, .body)) }
        if !controller.email.isBlank { blocks.append(PdfExport.Text(controller.email, .body)) }
        if !controller.phone.isBlank { blocks.append(PdfExport.Text(controller.phone, .body)) }
        let place = [controller.postalCode, controller.city].filter { !$0.isBlank }.joined(separator: " ")
        let lines = [controller.street, place].filter { !$0.isBlank }
        if !lines.isEmpty { blocks.append(PdfExport.Text(lines.joined(separator: ", "), .body)) }
        panel(PdfExport.Panel(s.controllerTitle, blocks))
    }

    func contract(_ p: HandoverProtocol) {
        panel(PdfExport.Panel(s.contract, [
            PdfExport.Fields([
                (s.monthlyRent, p.contract.monthlyRentChf),
                (s.serviceCharges, p.contract.serviceChargesChf),
                (s.noticeDate, SwissDate.display(p.contract.noticeDate)),
            ]),
            PdfExport.Fields([
                (s.leaseConcludedOn, SwissDate.display(p.contract.conclusionDate)),
                (s.tenancyStart, SwissDate.display(p.contract.startDate)),
                (s.tenancyEnd, SwissDate.display(p.contract.endDate)),
            ]),
        ]))
    }

    func deposit(_ p: HandoverProtocol) {
        let blocks: [any PdfExport.Block]
        switch p.deposit.kind {
        case .none:
            blocks = [PdfExport.Text(s.depositKind(.none), .body)]
        case .insurance:
            blocks = [PdfExport.Fields([(s.depositProvider, p.deposit.provider), (s.depositPolicy, p.deposit.policyNo), (s.depositAmount, p.deposit.amountChf)])]
        case .bankAccount:
            blocks = [PdfExport.Fields([(s.depositBankName, p.deposit.bank), (s.depositAccount, p.deposit.account), (s.depositAmount, p.deposit.amountChf)])]
        case .unknown:
            blocks = [PdfExport.Text(s.toVerify, .body)]
        }
        panel(PdfExport.Panel(s.deposit, blocks))
    }

    func meters(_ p: HandoverProtocol) {
        panel(PdfExport.Panel(s.meters, [
            PdfExport.Fields([(s.meterElec1, p.meters.electricity1), (s.meterElec2, p.meters.electricity2), (s.meterGas, p.meters.gas)]),
            PdfExport.Fields([(s.meterWater, p.meters.water), (s.meterHotWater, p.meters.hotWater), (s.meterOil, p.meters.heatingOil)]),
        ]))
    }

    /// The keys: the transfer's status as the panel's pill, then one chip per kind with its count.
    func keys(_ p: HandoverProtocol) {
        let tone: PdfExport.PillTone
        switch p.keyTransfer {
        case .allTransferred: tone = .seal
        case .incomplete: tone = .warning
        case .noPhysicalKeys, .notRecorded: tone = .dim
        }
        var blocks: [any PdfExport.Block] = []
        if !p.keyTransferNote.isBlank { blocks.append(PdfExport.Text(p.keyTransferNote, .small)) }
        if p.keyTransfer != .noPhysicalKeys {
            let chips = p.keys.filter { $0.count >= 1 }.map { k -> PdfExport.Chip in
                let label = k.kind == .other && !k.label.isBlank ? k.label : s.keyKind(k.kind)
                return PdfExport.Chip("\(label): \(k.count)")
            }
            blocks.append(chips.isEmpty ? PdfExport.Text("–", .body) : PdfExport.Chips(chips))
            // Older records counted a room's own door keys inside the room. Those still print,
            // once, here rather than twice as they used to.
            let roomKeys = p.rooms.filter { $0.keysCount > 0 }
            if !roomKeys.isEmpty { blocks.append(PdfExport.Chips(roomKeys.map { PdfExport.Chip("\(Outline.roomName($0, s)): \($0.keysCount)") })) }
        }
        if p.selfMadeKeys { blocks.append(PdfExport.Text(s.selfMadeKeys, .body)) }
        panel(PdfExport.Panel(s.keysLabel, blocks, pill: PdfExport.Pill(s.keyTransfer(p.keyTransfer), tone)))
    }
}
