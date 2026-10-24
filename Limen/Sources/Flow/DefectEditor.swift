import LimenKit
import SwiftUI

/// The defect editor, over the whole screen: a finding deserves the room a dialog does not give
/// it. It serves a room finding and a finding about a supplied object alike, since everything
/// below the heading is the same question either way.
struct DefectEditor: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    let defectId: String

    var body: some View {
        if let d = p.defects.first(where: { $0.id == defectId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        IconKey(glyph: .back, label: s.back) { model.closeDefect() }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(p.defectPlace(d, s).uppercased()).font(LimenType.labelLarge).foregroundStyle(colors.ink)
                            if let label = p.defectItemLabel(d, s) {
                                Text(label).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Panel(label: s.defects, info: s.tipDefect(), warning: true) {
                        Field(label: s.defectText, value: d.text, singleLine: false) { value in
                            model.updateDefect(defectId) { var x = $0; x.text = value; return x }
                        }
                    }
                    if !locked || !d.photos.isEmpty {
                        Panel(label: s.photos) {
                            VStack(alignment: .leading, spacing: 8) {
                                if !locked {
                                    PhotoIntakeKeys(owner: defectId, kind: .defect) { file, source in model.attachPhoto(defectId, source: file, photoSource: source) }
                                }
                                if !d.photos.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(d.photos, id: \.self) { name in
                                                PhotoThumb(name: name, evidence: d.photoEvidence.first { $0.file == name }) { model.removePhoto(defectId, name: name) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if p.kind == .exit {
                        ForEach(p.parties.filter { $0.role == .tenant }, id: \.uiKey) { party in
                            let key = party.participantKey()
                            let position = d.participantPositions[key] ?? (party.id.isBlank ? TenantPosition(response: d.tenantResponse, comment: d.tenantComment) : TenantPosition())
                            Panel(label: "\(s.tenantResponseLabel) · \(party.name.ifBlank(s.role(.tenant)))", info: s.tipNormalWear()) {
                                VStack(alignment: .leading, spacing: 8) {
                                    PillRow(options: TenantResponse.allCases.map { ($0, s.tenantResponse($0)) }, current: position.response, dense: true, enabled: !locked) { response in
                                        model.updateDefect(defectId) { defect in
                                            var next = defect
                                            next.participantPositions[key] = TenantPosition(response: response, comment: position.comment)
                                            return next
                                        }
                                    }
                                    Field(label: s.tenantComment, value: position.comment, singleLine: false) { value in
                                        model.updateDefect(defectId) { defect in
                                            var next = defect
                                            next.participantPositions[key] = TenantPosition(response: position.response, comment: value)
                                            return next
                                        }
                                    }
                                }
                            }
                        }
                        Group {
                            Panel(label: s.chargedToTenant, info: s.tipCharged()) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle(label: s.chargedToTenant, on: d.chargedToTenant, enabled: !locked) {
                                        model.updateDefect(defectId) { var x = $0; x.chargedToTenant.toggle(); return x }
                                    }
                                    Text(s.fixByLabel).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                                    PillRow(options: [(FixBy.open, s.fixOpen), (.tenant, s.role(.tenant)), (.landlord, s.role(.landlord))], current: d.fixBy, dense: true, enabled: !locked) { f in
                                        model.updateDefect(defectId) { var x = $0; x.fixBy = f; return x }
                                    }
                                    WeightedRow(weights: [1, 1.4]) {
                                        DateField(label: s.fixDeadline, stored: d.fixDeadline, fieldKey: "defect.\(d.id).fixDeadline") { value in
                                            model.updateDefect(defectId) { var x = $0; x.fixDeadline = value; return x }
                                        }
                                        Field(label: s.costNote, value: d.costNote) { value in
                                            model.updateDefect(defectId) { var x = $0; x.costNote = value; return x }
                                        }
                                    }
                                    Field(label: s.reservationLabel, value: d.reservation) { value in
                                        model.updateDefect(defectId) { var x = $0; x.reservation = value; return x }
                                    }
                                }
                            }
                        }
                        if d.chargedToTenant { WearAssessment(p: p, defectId: d.id) }
                    }
                    if p.kind == .entry {
                        Panel(label: s.reservationLabel) {
                            Field(label: s.reservationLabel, value: d.reservation) { value in
                                model.updateDefect(defectId) { var x = $0; x.reservation = value; return x }
                            }
                        }
                    }
                    WeightedRow(weights: locked ? [1] : [1, 1.6]) {
                        if !locked {
                            IconKey(glyph: .delete, label: s.delete, destructive: true, tick: .reject, stretch: true) { model.removeDefect(defectId) }
                        }
                        IconKey(glyph: .confirm, label: s.done, fillColor: colors.action, outlineColor: colors.action, tint: colors.onInk, tick: .confirm, stretch: true) { model.closeDefect() }
                    }
                    Spacer().frame(height: 12)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .readable()
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.plate.ignoresSafeArea())
        }
    }
}

/// The Zeitwert calculation belongs to a specific charged defect, not the home screen. Pick the
/// item, state its age and repair cost, then use the tenant share in that defect's record.
struct WearAssessment: View {
    @Environment(LimenModel.self) private var model
    let p: HandoverProtocol
    let defectId: String
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    @State private var showTable = false

    private var estimate: ReplacementEstimate { p.details.estimates[defectId] ?? ReplacementEstimate() }
    /// The row is stored by its enum name, as Android stores it, so the paper names it in the
    /// document's language; a lifespan typed by hand leaves it blank, which reads as Own value.
    private var picked: LifeKey? { LifeKey(rawValue: estimate.basis) }
    private var lifespan: String { estimate.lifeYears }
    private var age: String { estimate.ageYears }
    private var cost: String { estimate.replacementChf }

    private func update(_ change: (inout ReplacementEstimate) -> Void) {
        var next = estimate
        change(&next)
        model.edit { var record = $0; record.details.estimates[defectId] = next; return record }
    }

    var body: some View {
        let lifespanV = swissNumber(lifespan) ?? 0
        let ageV = swissNumber(age)
        let costV = swissNumber(cost)
        VStack(spacing: 10) {
            // Offered back through the undo bar, as the other entries of the dossier are.
            if !locked, p.details.estimates[defectId] != nil {
                SmallKey(label: s.delete) { model.removeEstimate(defectId) }
            }
            Panel(label: s.faceValue, info: s.tipZeitwert()) {
                VStack(alignment: .leading, spacing: 8) {
                    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                    Button {
                        Haptics.play(.key)
                        showTable.toggle()
                    } label: {
                        HStack {
                            Text(picked.map(s.life) ?? s.customLifespan).font(LimenType.bodyMedium).foregroundStyle(colors.ink).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: showTable ? "chevron.up" : "chevron.down").foregroundStyle(colors.inkDim)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(colors.input, in: shape)
                        .overlay(shape.strokeBorder(colors.actionOutline, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    if showTable {
                        Revealed(key: showTable) {
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(Lifespans.table, id: \.key) { row in
                                        Button {
                                            Haptics.play(.key)
                                            update { $0.lifeYears = String(Int(row.years)); $0.basis = row.key.rawValue }
                                            showTable = false
                                        } label: {
                                            HStack {
                                                Text(s.life(row.key)).font(LimenType.bodyMedium).foregroundStyle(colors.ink).frame(maxWidth: .infinity, alignment: .leading)
                                                Text(String(Int(row.years))).font(LimenType.mono(14)).foregroundStyle(colors.inkDim)
                                            }
                                            .padding(8)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(height: 300)
                        }
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Field(label: s.lifespanYears, value: lifespan, keyboard: .decimalPad) { v in
                            update { $0.lifeYears = String(v.prefix(5)); $0.basis = "" }
                        }
                        Field(label: s.ageYears, value: age, keyboard: .decimalPad) { value in update { $0.ageYears = String(value.prefix(5)) } }
                    }
                    Text(s.estimateNotice).font(LimenType.bodySmall).foregroundStyle(colors.ink)
                    Field(label: s.sourceLabel, value: estimate.source) { value in update { $0.source = value } }
                    DateField(label: s.handoverDate, stored: estimate.date, fieldKey: "estimate.\(defectId).date") { value in update { $0.date = value } }
                    Field(label: s.repairCost, value: cost, keyboard: .decimalPad, isError: !cost.isBlank && swissNumber(cost) == nil) { value in update { $0.replacementChf = String(value.prefix(12)) } }
                }
            }
            if lifespanV > 0, let ageV {
                let fraction = Zeitwert.remainingFraction(lifespanYears: lifespanV, ageYears: ageV)
                let share = costV.map { Zeitwert.tenantShare(costChf: $0, lifespanYears: lifespanV, ageYears: ageV) }
                let zero = share == 0 || (share == nil && fraction == 0)
                Panel(label: s.tenantShare) {
                    VStack(spacing: 4) {
                        Text(share.map { "CHF " + String(format: "%.0f", $0) } ?? String(format: "%.0f%%", fraction * 100))
                            .font(LimenType.mono(54, like: .largeTitle))
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(zero ? colors.seal : colors.ink)
                        Text("\(s.remainingValue): " + String(format: "%.0f%%", fraction * 100)).font(LimenType.labelLarge).foregroundStyle(colors.inkDim)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// A figure as a person actually types it here: "1'200.50", "1 200,50", "1200.5". The
    /// apostrophe is the Swiss thousands separator, and a cost entered the normal way used to
    /// parse as nothing.
    private func swissNumber(_ typed: String) -> Double? {
        guard let value = Double(typed.filter { !"'’".contains($0) && !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")), value.isFinite, value >= 0 else { return nil }
        return value
    }
}
