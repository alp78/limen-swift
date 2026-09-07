import LimenKit
import SwiftUI

private struct ReviewLine: View {
    @Environment(\.limen) private var colors
    let label: String
    let value: String

    var body: some View {
        if !value.isBlank {
            HStack(alignment: .top, spacing: 8) {
                Text(label).font(LimenType.labelSmall).foregroundStyle(colors.inkDim).frame(maxWidth: .infinity, alignment: .leading).layoutPriority(0.42)
                Text(value).font(LimenType.bodyMedium).foregroundStyle(colors.ink).frame(maxWidth: .infinity, alignment: .leading).layoutPriority(0.58)
            }
        }
    }
}

struct ReviewStep: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let p: HandoverProtocol

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                identity
                legalOverlay
                inspection
                dossier
                Panel(label: "\(s.defects) (\(p.defects.count))", info: s.tipCharged(), warning: !p.defects.isEmpty) {
                    if p.defects.isEmpty {
                        Text(s.nothingYet).font(LimenType.bodyMedium).foregroundStyle(colors.inkDim)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(p.defects.enumerated()), id: \.element.id) { i, d in
                                HStack(alignment: .center) {
                                    Text("\(i + 1).").font(LimenType.mono(14)).foregroundStyle(colors.inkDim).frame(width: 30, alignment: .leading)
                                    DefectLine(p: p, d: d, showPlace: true)
                                }
                            }
                        }
                    }
                }
                BigKey(label: s.stepSign.uppercased()) { model.goTo(.sign) }
                Spacer().frame(height: 12)
            }
        }
    }

    private var identity: some View {
        VStack(spacing: 10) {
            Panel(label: s.objectLabel) {
                VStack(spacing: 5) {
                    ReviewLine(label: s.protocolKind, value: p.kind == .entry ? s.entry : s.exit)
                    ReviewLine(label: s.address, value: p.address)
                    ReviewLine(label: s.place, value: p.place)
                    ReviewLine(label: s.cantonLabel, value: p.objectCanton.map(s.canton) ?? "")
                    ReviewLine(label: s.objectDetail, value: p.objectDetail)
                    // Swiss, like every other date the operator sees and every date on the paper.
                    ReviewLine(label: s.handoverDate, value: [SwissDate.display(p.handoverDate), p.handoverTime].filter { !$0.isBlank }.joined(separator: " · "))
                    ReviewLine(label: s.legalBasis, value: s.legalProfile(p.legalProfile()))
                }
            }
            Panel(label: s.parties) {
                VStack(spacing: 6) {
                    ForEach(Array(p.parties.filter { !$0.name.isBlank }.enumerated()), id: \.offset) { _, party in
                        let detail = [
                            party.name,
                            party.representedBy.isBlank ? nil : "\(s.representedBy): \(party.representedBy)",
                            party.address.isBlank ? nil : party.address,
                            party.phone.isBlank ? nil : party.phone,
                            party.email.isBlank ? nil : party.email,
                        ].compactMap { $0 }.joined(separator: " · ")
                        ReviewLine(label: s.role(party.role), value: detail)
                    }
                }
            }
            if !p.controllerIdentity.isBlank {
                let c = p.controllerIdentity
                Panel(label: s.controllerTitle) {
                    VStack(spacing: 5) {
                        ReviewLine(label: s.organisation, value: c.organisation)
                        ReviewLine(label: s.controllerContact, value: c.contactName)
                        ReviewLine(label: s.identityAddress, value: [c.street, [c.postalCode, c.city].filter { !$0.isBlank }.joined(separator: " ")].filter { !$0.isBlank }.joined(separator: ", "))
                        // Two rows, not one joined row under the email label: a controller who gave
                        // only a phone number was reading "Email: +41 79 ..." on the screen they
                        // check before finalizing. ReviewLine already hides a blank value.
                        ReviewLine(label: s.email, value: c.email)
                        ReviewLine(label: s.phoneNumber, value: c.phone)
                    }
                }
            }
        }
    }

    @ViewBuilder private var legalOverlay: some View {
        if let overlay = p.resolvedLegalOverlay() {
            let requirements = p.isFinalized() && !p.legalOverlay.checks.isEmpty ? p.legalOverlay.checks.keys.sorted { $0.ordinal < $1.ordinal } : overlay.requirements
            Panel(label: s.legalOverlayTitle) {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        CantonFlag(canton: overlay.canton, size: 28)
                        Text(s.canton(overlay.canton)).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                        Spacer()
                    }
                    if p.kind == .entry {
                        ReviewLine(label: s.initialRentForm, value: s.initialRentFormRule(overlay.initialRentFormRule))
                    }
                    ForEach(requirements, id: \.self) { requirement in
                        ReviewLine(label: s.legalRequirement(requirement), value: p.legalOverlay.status(requirement).map(s.legalCheckStatus) ?? s.stillMissing)
                    }
                    ReviewLine(label: s.legalOverlayNote, value: p.legalOverlay.note)
                }
            }
        }
    }

    private var inspection: some View {
        Panel(label: s.stepInspection) {
            VStack(spacing: 5) {
                ForEach(p.rooms, id: \.id) { room in
                    let count = p.defects.filter { $0.roomId == room.id && $0.objectId.isBlank }.count
                    ReviewLine(label: room.name.ifBlank(s.room(room.kind)), value: [room.inspected ? s.roomInspected : s.notInspected, count > 0 ? s.countDefects(count) : nil].compactMap { $0 }.joined(separator: " · "))
                }
                ForEach(p.objects, id: \.id) { entry in
                    let count = p.defects.filter { $0.objectId == entry.id }.count
                    ReviewLine(label: entry.displayName(s), value: [entry.inspected ? s.objectInspected : s.notInspected, count > 0 ? s.countDefects(count) : nil].compactMap { $0 }.joined(separator: " · "))
                }
            }
        }
    }

    private var keysLine: String {
        let keyCounts = p.keys.filter { $0.count >= 1 }.map { key in
            "\(key.kind == .other && !key.label.isBlank ? key.label : s.keyKind(key.kind)): \(key.count)"
        }
        let roomCounts = p.rooms.filter { $0.keysCount > 0 }.map { room in "\(room.name.ifBlank(s.room(room.kind))): \(room.keysCount)" }
        let joined = (keyCounts + roomCounts).joined(separator: ", ")
        return [s.keyTransfer(p.keyTransfer), joined.isBlank ? nil : joined, p.keyTransferNote.isBlank ? nil : p.keyTransferNote, p.selfMadeKeys ? s.selfMadeKeys : nil].compactMap { $0 }.joined(separator: " · ")
    }

    private var dossier: some View {
        Panel(label: s.stepDossier) {
            VStack(spacing: 5) {
                if p.carries(.contract) {
                    let c = p.contract
                    ReviewLine(label: s.contract, value: [
                        c.monthlyRentChf.isBlank ? nil : "\(s.monthlyRent): \(c.monthlyRentChf)",
                        c.serviceChargesChf.isBlank ? nil : "\(s.serviceCharges): \(c.serviceChargesChf)",
                        c.conclusionDate.isBlank ? nil : "\(s.leaseConcludedOn): \(SwissDate.display(c.conclusionDate))",
                        c.startDate.isBlank ? nil : "\(s.tenancyStart): \(SwissDate.display(c.startDate))",
                        c.endDate.isBlank ? nil : "\(s.tenancyEnd): \(SwissDate.display(c.endDate))",
                        c.noticeDate.isBlank ? nil : "\(s.noticeDate): \(SwissDate.display(c.noticeDate))",
                    ].compactMap { $0 }.joined(separator: " · "))
                }
                if p.carries(.deposit) {
                    let d = p.deposit
                    let institute: String = d.kind == .bankAccount ? d.bank : (d.kind == .insurance ? d.provider : "")
                    ReviewLine(label: s.deposit, value: [
                        s.depositKind(d.kind),
                        d.amountChf.isBlank ? nil : "CHF \(d.amountChf)",
                        institute.isBlank ? nil : institute,
                        d.policyNo.isBlank ? nil : d.policyNo,
                        d.account.isBlank ? nil : d.account,
                    ].compactMap { $0 }.joined(separator: " · "))
                }
                if p.carries(.meters) {
                    let meters = [(s.meterElec1, p.meters.electricity1), (s.meterElec2, p.meters.electricity2), (s.meterGas, p.meters.gas), (s.meterWater, p.meters.water), (s.meterHotWater, p.meters.hotWater), (s.meterOil, p.meters.heatingOil)].filter { !$0.1.isBlank }
                    ReviewLine(label: s.meters, value: meters.map { "\($0.0): \($0.1)" }.joined(separator: " · "))
                }
                if p.carries(.keys) {
                    ReviewLine(label: s.keysLabel, value: keysLine)
                }
                if p.carries(.notes) {
                    ReviewLine(label: s.remarks, value: p.remarks)
                    ReviewLine(label: s.chargesBy, value: SwissDate.display(p.chargesStatementBy))
                }
            }
        }
    }
}

/// The handover record signature. Refusal is a recorded outcome, not a dead end.
struct SignStep: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    @State private var padTarget: Role?

    var body: some View {
        let issues = model.completionIssues(p)
        let canExport = p.isFinalized() || (issues.isEmpty && !model.finalizing)
        ScrollView {
            VStack(spacing: 10) {
                Panel(label: s.signRecordTitle, info: s.tipRecord()) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Who has to sign at all. This decides the rows below, which is why it
                        // sits here rather than filed under the dossier's notes.
                        HStack {
                            Toggle(label: s.oneSided, on: p.oneSided, enabled: !locked) {
                                model.edit { current in
                                    var next = current
                                    if current.oneSided {
                                        next.oneSided = false
                                        next.unilateralReason = nil
                                        next.unilateralNote = ""
                                    } else {
                                        next.oneSided = true
                                    }
                                    return next
                                }
                            }
                            InfoTip(tip: s.tipOneSided())
                        }
                        if p.oneSided {
                            Text(s.infoOneSided).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                            FlowRow(spacing: 6) {
                                ForEach(UnilateralReason.allCases, id: \.self) { reason in
                                    Chip(label: s.unilateralReason(reason), active: p.unilateralReason == reason) {
                                        model.edit { var x = $0; x.unilateralReason = reason; return x }
                                    }
                                }
                            }
                            Field(label: s.unilateralNote, value: p.unilateralNote, singleLine: false) { v in model.edit { var x = $0; x.unilateralNote = v; return x } }
                        }
                        Text(s.reservationBeforeSign).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                        ForEach(model.requiredRecordRoles(p), id: \.self) { role in
                            SignRow(p: p, role: role, plane: .record) { padTarget = role }
                        }
                        Text(s.inkEvidenceNotice).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                    }
                }
                // A record that is already frozen has nothing to freeze.
                if !locked {
                    Panel(label: s.finalizeRecord, info: s.tipFinalize()) {
                        VStack(alignment: .leading, spacing: 8) {
                            if !issues.isEmpty {
                                Text(s.finalizationNeeds).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                                ForEach(issues, id: \.self) { issue in
                                    Text("• \(s.finalizationIssue(issue))").font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                                }
                            }
                            if model.finalizationError {
                                Text(s.finalizationFailed).font(LimenType.labelSmall).foregroundStyle(colors.ink)
                            }
                            BigKey(label: model.finalizing ? s.finalizing : s.finalizeRecord, active: issues.isEmpty && !model.finalizing, enabled: issues.isEmpty && !model.finalizing) { model.finalizeProtocol() }
                        }
                    }
                }
                BigKey(label: s.stepExport.uppercased(), active: canExport, enabled: canExport) { model.goTo(.export) }
                if !locked {
                    BigKey(label: s.saveAsDraft) { model.closeFlow() }
                }
                Spacer().frame(height: 12)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .fullScreenCover(item: $padTarget) { role in
            SignPadOverlay(title: "\(s.signRecordTitle) · \(s.role(role))", meaning: s.tipRecord().lead, onKeep: { png in
                model.keepSignature(role, plane: .record, png: png)
                padTarget = nil
            }, onCancel: { padTarget = nil })
            .environment(\.limen, colors)
            .environment(\.str, s)
        }
    }
}

extension Role: Identifiable {
    public var id: String { rawValue }
}

private struct SignRow: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    let role: Role
    let plane: Plane
    let onSign: () -> Void

    var body: some View {
        let sig = p.signatures.first { $0.role == role && $0.plane == plane }
        let current = sig.map(p.isCurrent) == true
        let pendingReservation = p.pendingRecordReservations[role] ?? sig?.reservation ?? ""
        // The status: the one place besides the case's chip where the seal colour appears.
        let status: (String, Bool) = {
            guard let sig else { return (s.notSigned, false) }
            if !current { return (s.resignRequired, false) }
            if sig.refused { return (s.refusedNote, false) }
            return (s.signed, true)
        }()
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.role(role)).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                    Text(status.0).font(LimenType.labelSmall).foregroundStyle(status.1 ? colors.seal : colors.inkDim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if locked {
                    // Nothing to offer: the ink is part of what the fingerprint covers.
                } else if sig == nil || !current {
                    IconKey(glyph: .edit, label: s.signKey, onPress: onSign)
                    IconKey(glyph: .cancel, label: s.refusedKey, fillColor: colors.danger, outlineColor: colors.dangerOutline, tint: colors.dangerOutline, tick: .reject) { model.refuseSignature(role, plane: plane) }
                } else {
                    IconKey(glyph: .clear, label: s.clearInk, destructive: true) { model.clearSignature(role, plane: plane) }
                }
            }
            if !locked, !current {
                Field(label: s.reservationLabel, value: pendingReservation) { model.setRecordReservation(role, $0) }
            } else if let sig, !sig.reservation.isBlank {
                Text("\(s.reservationLabel): \(sig.reservation)").font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
            }
        }
    }
}

/// The way out: the document's language, the export itself, the result card, and the deposit's
/// next step, which is the last thing both parties read at the door.
struct ExportStep: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let p: HandoverProtocol
    @State private var sharing: ExportedFile?
    @State private var previewing: ExportedFile?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if !p.isFinalized() {
                    Panel(label: s.finalizeRecord) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(s.exportBlocked).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                            SmallKey(label: s.stepSign.uppercased(), stretch: true) { model.goTo(.sign) }
                        }
                    }
                    if let issue = model.exportIssue {
                        Text(s.exportIssue(issue)).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                    }
                    BigKey(label: s.exportPdf, active: false, enabled: false) {}
                    BigKey(label: s.saveAsDraft) { model.closeFlow() }
                } else {
                    Panel(label: s.pdfFinalized) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(s.pdfFinalized).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                            Text("\(s.fingerprint): \(p.evidenceFingerprint.prefix(20))").font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                            if !p.amendedFromId.isBlank {
                                Text("\(s.pdfAmends): \(p.amendedFromId)").font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                            }
                        }
                    }
                    Panel(label: s.pdfLanguage) {
                        PillRow(options: Lang.allCases.map { ($0, $0.rawValue.uppercased()) }, current: model.pdfLang ?? model.lang, dense: true) { model.selectPdfLang($0) }
                    }
                    let deliveryNeedsExport = p.deliveryMetadataEpochMs > p.exportedEpochMs
                    if deliveryNeedsExport {
                        Panel(label: s.deliveryChanged, warning: true) {
                            Text(s.deliveryChangedBody).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                        }
                    }
                    BigKey(label: model.exporting ? "…" : (deliveryNeedsExport ? s.exportUpdatedFinalCopy : s.exportPdf), active: !model.exporting, enabled: !model.exporting) { model.exportPdf() }
                    if let issue = model.exportIssue {
                        Text(s.exportIssue(issue)).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                    }
                    if let file = model.exported {
                        Revealed(key: file.displayName) {
                            Panel(label: s.exported, info: s.tipShareNow()) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(file.displayName).font(LimenType.titleMedium).foregroundStyle(colors.ink)
                                    Text("\(s.exportedTo) Limen · \(max(file.bytes / 1024, 1)) KB").font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                                    HStack(spacing: 8) {
                                        IconKey(glyph: .open, label: s.open, stretch: true) { previewing = file }
                                        IconKey(glyph: .share, label: s.share, stretch: true) { sharing = file }
                                    }
                                }
                            }
                        }
                    }
                    if p.isExported() { CopyDeliveryPanel(p: p) }
                    // The deposit's next step, on screen as well as in the PDF.
                    if p.kind == .exit, p.deposit.kind != .none {
                        Panel(label: s.releaseTitle) {
                            Text(p.deposit.kind == .bankAccount ? s.releaseBank : s.releaseInsurance).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                        }
                    }
                    Panel(label: s.amendRecord, info: s.tipAmend()) {
                        VStack(alignment: .leading, spacing: 8) {
                            BigKey(label: model.amendmentInProgress ? s.amending : s.amendRecord, active: !model.amendmentInProgress, enabled: !model.amendmentInProgress) { model.createAmendment() }
                            if model.amendmentError {
                                Text(s.amendFailed).font(LimenType.bodySmall).foregroundStyle(colors.dangerOutline)
                            }
                        }
                    }
                    // Closed only when nothing is still being written.
                    SmallKey(label: model.exporting ? "…" : s.done, enabled: !model.exporting, stretch: true) { model.closeFlow() }
                }
                Spacer().frame(height: 12)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        // The finished document is the other moment that ends something, and it arrives after
        // the key was released, so the confirmation is played by the result rather than the tap.
        .onChange(of: model.exported) { _, file in if file != nil { Haptics.play(.confirm) } }
        .sheet(item: $sharing) { file in ShareSheet(url: file.url) }
        .sheet(item: $previewing) { file in
            NavigationStack {
                PDFPreview(url: file.url)
                    .navigationTitle(file.displayName)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(s.done.capitalized) { previewing = nil } } }
            }
        }
    }
}

extension ExportedFile: Identifiable {
    public var id: String { url.path }
}

private struct CopyDeliveryPanel: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let p: HandoverProtocol
    @State private var tenantDetail = ""
    @State private var landlordDetail = ""

    var body: some View {
        Panel(label: s.copyDelivery) {
            VStack(alignment: .leading, spacing: 10) {
                Text(s.deliverySelfDeclared).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                ForEach([Role.tenant, .landlord], id: \.self) { role in
                    let receipt = p.deliveryReceipts.first { $0.role == role }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(s.role(role)).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                        if let receipt {
                            HStack {
                                Text("\(s.deliveryMethod(receipt.method)) · \(deliveryMoment(receipt.epochMs))").font(LimenType.labelSmall).foregroundStyle(colors.seal).frame(maxWidth: .infinity, alignment: .leading)
                                IconKey(glyph: .clear, label: s.clearDelivery, destructive: true) { model.clearDelivery(role) }
                            }
                            if !receipt.note.isBlank {
                                Text(receipt.note).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                            }
                        } else {
                            Text(s.recordCopyFor).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                            let detail = role == .tenant ? tenantDetail : landlordDetail
                            Field(label: s.deliveryDetail, value: detail, editableWhenLocked: true) { value in
                                if role == .tenant { tenantDetail = value } else { landlordDetail = value }
                            }
                            FlowRow(spacing: 6) {
                                ForEach(DeliveryMethod.allCases, id: \.self) { method in
                                    Chip(label: s.deliveryMethod(method), dim: false, enabled: method != .other || !detail.isBlank) { model.recordDelivery(role, method: method, note: detail) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: p.id) { _, _ in
            tenantDetail = ""
            landlordDetail = ""
        }
    }

    private func deliveryMoment(_ epochMs: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000))
    }
}

/// The system share sheet, the chooser ACTION_SEND opened.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
