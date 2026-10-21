import CoreGraphics
import Foundation

/// The closing sections: the supplemental panels, the remarks, the signatures, the copies
/// delivered and the deposit release.
extension PdfExport.Sheet {
    /// The supplemental sections shared with the preview, one panel per heading.
    func extras(_ p: HandoverProtocol) {
        for section in RecordContent.extraContent(record: p, strings: s) {
            panel(PdfExport.Panel(section.title, section.paragraphs.map { PdfExport.Text($0, .body) }))
        }
    }

    /// The Notes component: free remarks and the service-charge date, when it is on the record.
    func remarks(_ p: HandoverProtocol) {
        if !Outline.remarks(p) { return }
        var blocks: [any PdfExport.Block] = []
        if !p.remarks.isBlank { blocks.append(PdfExport.Text(p.remarks, .body)) }
        if !p.chargesStatementBy.isBlank {
            if !p.remarks.isBlank { blocks.append(PdfExport.Gap(PdfTokens.labelGap)) }
            blocks.append(PdfExport.Text("\(s.chargesBy) \(SwissDate.display(p.chargesStatementBy))", .body))
        }
        panel(PdfExport.Panel(s.remarks, blocks))
    }

    /// The record signatures, always printed, with their meaning above the ink. A handover one
    /// party did not attend is a statement about these signatures, so it is the panel's pill and
    /// its first lines, unconditionally: under the optional remarks it vanished from the paper
    /// whenever that component was not added.
    func signatures(_ p: HandoverProtocol, _ signatureDir: URL) {
        var blocks: [any PdfExport.Block] = []
        if p.oneSided {
            if let reason = p.unilateralReason { blocks.append(PdfExport.Text("\(s.unilateralReasonLabel): \(s.unilateralReason(reason))", .body)) }
            if !p.unilateralNote.isBlank { blocks.append(PdfExport.Text(p.unilateralNote, .small)) }
            blocks.append(PdfExport.Text(s.infoOneSided, .small))
            blocks.append(PdfExport.Gap(PdfTokens.labelGap))
        }
        blocks.append(PdfExport.Text(s.signRecordMeaning, .small))
        blocks.append(PdfExport.Gap(PdfTokens.labelGap))
        blocks += plane(p, signatureDir, .record)
        blocks.append(PdfExport.Text(s.inkEvidenceNotice, .small))
        // The Swiss ritual, said on the document itself: two identical papers, one per party. In
        // Vaud the RULV require exactly that, and a tenant who reads it here knows to leave the
        // flat holding one.
        blocks.append(PdfExport.Gap(6))
        blocks.append(PdfExport.Text(s.pdfTwoCopies, .small))
        panel(PdfExport.Panel(s.signRecordTitle, blocks, pill: p.oneSided ? PdfExport.Pill(s.oneSided, .warning) : nil))
        if p.signatures.contains(where: { $0.plane == .costs }) { panel(PdfExport.Panel(s.costSignatureTitle, plane(p, signatureDir, .costs))) }
    }

    private func plane(_ p: HandoverProtocol, _ dir: URL, _ plane: Plane) -> [any PdfExport.Block] {
        var blocks: [any PdfExport.Block] = []
        let current = p.signatures.filter { $0.plane == plane && p.isCurrent($0) }
        if plane == .record {
            // A draft's preview names every participant whose outcome is still missing, with the
            // reservation already recorded for them: the review this port adds before the record
            // is frozen. A finalized record has every required outcome, so this prints nothing on it.
            for party in CompletionRules.requiredRecordParticipants(p) {
                let signed = current.contains { $0.participantId.isBlank ? party.id.isBlank && $0.role == party.role : $0.participantId == party.participantKey() }
                if signed { continue }
                blocks.append(PdfExport.Text("\(party.signerName()) (\(s.role(party.role)))", .bodyMedium, keepWithNext: true))
                blocks.append(PdfExport.Text(s.notSigned, .body))
                let reservation = p.reservationFor(party: party)
                if !reservation.isBlank { blocks.append(PdfExport.Text("\(s.reservationLabel): \(reservation)", .small)) }
                blocks.append(PdfExport.Gap(14))
            }
        }
        if current.isEmpty {
            if blocks.isEmpty { blocks.append(PdfExport.Text(s.notSigned, .body)) }
            return blocks
        }
        for sig in current {
            let note: String?
            if sig.refused || !sig.outcome.isBlank {
                note = sig.outcome == "absent" ? s.absentOutcome : sig.outcome == "unable" ? s.unableToDraw : s.refusedNote
            } else {
                note = nil
            }
            var image: CGImage?
            if note == nil, !sig.file.isBlank {
                image = PhotoDecode.sampled(dir.appendingPathComponent(sig.file), targetWidth: 840)
                // A signature the record names and the store cannot render is a document that cannot be made.
                if image == nil { renderingFailed = true }
            }
            var caption: [any PdfExport.Block] = [PdfExport.Text(sig.name.isBlank ? s.role(sig.role) : "\(sig.name) (\(s.role(sig.role)))", .bodyMedium)]
            if !sig.reservation.isBlank { caption.append(PdfExport.Text("\(s.reservationLabel): \(sig.reservation)", .small)) }
            if sig.epochMs > 0 { caption.append(PdfExport.Text("\(s.capturedOn): \(PdfExport.formatMoment(sig.epochMs))", .small)) }
            caption.append(PdfExport.Text("\(s.revisionLabel): \(sig.contentRevision)", .small))
            blocks.append(PdfExport.Ink(image: image, alt: "\(s.signRecordTitle): \(sig.name)", note: note, caption: caption))
        }
        return blocks
    }

    func delivery(_ p: HandoverProtocol) {
        if p.deliveryReceipts.isEmpty { return }
        var blocks: [any PdfExport.Block] = [PdfExport.Text(s.deliverySelfDeclared, .small)]
        let order = Role.allCases
        for receipt in p.deliveryReceipts.sorted(by: { (order.firstIndex(of: $0.role) ?? 0) < (order.firstIndex(of: $1.role) ?? 0) }) {
            let name = p.parties.first {
                $0.participantKey() == receipt.participantId || receipt.participantId.isBlank && $0.id.isBlank && $0.role == receipt.role
            }?.name
            let who = name.map { $0.isBlank ? s.role(receipt.role) : "\($0) (\(s.role(receipt.role)))" } ?? s.role(receipt.role)
            blocks.append(PdfExport.Text(who, .bodyMedium, keepWithNext: true))
            var chips = [PdfExport.Chip(s.deliveryMethod(receipt.method))]
            if receipt.epochMs > 0 { chips.append(PdfExport.Chip(PdfExport.formatMoment(receipt.epochMs))) }
            blocks.append(PdfExport.Chips(chips))
            if !receipt.note.isBlank { blocks.append(PdfExport.Text(receipt.note, .small)) }
        }
        panel(PdfExport.Panel(s.copyDelivery, blocks))
    }

    /// The deposit release instruction, on an exit record that carries a deposit.
    func release(_ p: HandoverProtocol) {
        if !Outline.release(p) { return }
        var blocks: [any PdfExport.Block] = []
        switch p.deposit.kind {
        case .bankAccount:
            blocks.append(PdfExport.Text(s.releaseBank, .body))
        case .insurance:
            blocks.append(PdfExport.Text(s.releaseInsurance, .body))
            if !p.deposit.provider.isBlank {
                blocks.append(PdfExport.Gap(6))
                var pairs = [(s.depositProvider, p.deposit.provider)]
                if !p.deposit.policyNo.isBlank { pairs.append((s.depositPolicy, p.deposit.policyNo)) }
                blocks.append(PdfExport.Fields(pairs))
            }
        case .unknown:
            blocks.append(PdfExport.Text(s.toVerify, .body))
        case .none:
            break
        }
        panel(PdfExport.Panel(s.releaseTitle, blocks))
    }
}

extension PdfExport {
    /// Pinned to `en_US_POSIX` where Kotlin formats in the device locale: the document speaks the
    /// record's language rather than the phone's, and the stamp has to read the same on both.
    static func formatMoment(_ epochMs: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm z"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000))
    }
}
