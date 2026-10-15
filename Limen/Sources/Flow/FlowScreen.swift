import LimenKit
import SwiftUI

/// The protocol flow. Not a stepper: the hub is the home, and the two halves of a handover,
/// what is in the flat and what is on paper, are entered in whatever order the handover takes.
/// The draft is on disk after every keystroke, because the camera suspends this app whenever
/// it pleases.
struct FlowScreen: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previousStep: FlowStep = .hub
    @State private var flowWidth: CGFloat = 0

    var body: some View {
        if let p = model.working {
            let locked = p.isFinalized()
            let steps = FlowStep.allCases
            let forward = (steps.firstIndex(of: model.flowStep) ?? 0) >= (steps.firstIndex(of: previousStep) ?? 0)
            let direction: CGFloat = forward ? 1 : -1
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    FlowMast(p: p)
                    Spacer().frame(height: 8)
                    // Export carries the amendment door in full, with the sentence that explains it.
                    if locked, model.flowStep != .export {
                        SealBar()
                        Spacer().frame(height: 8)
                    }
                    ZStack {
                        switch model.flowStep {
                        case .hub: HubStep(p: p)
                        case .inspection: InspectionStep(p: p)
                        case .objects: ObjectsStep(p: p)
                        case .dossier: DossierStep(p: p)
                        case .review: ReviewStep(p: p)
                        case .sign: SignStep(p: p)
                        case .export: ExportStep(p: p)
                        }
                    }
                    .id(model.flowStep)
                    // Android's AnimatedContent slides the arriving step a tenth of the width in from
                    // the side it lies on while it fades in. The departing step only fades here: SwiftUI
                    // takes a departing view's transition from the render before the change, so a slide
                    // on it would run the wrong way on every reversal, and a custom modifier transition
                    // that read the direction late never let the screen settle for the UI tests.
                    .transition(.asymmetric(
                        insertion: .offset(x: direction * flowWidth / 10).combined(with: .opacity),
                        removal: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.size.width, initial: true) { _, width in flowWidth = width }
                })
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                // The stack behind keeps the full width so the plate does too; only the column of
                // content is capped. See View.readable.
                .readable()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.flowStep)
                .onChange(of: model.flowStep) { _, now in previousStep = now }
                if let notice = model.undoNotice {
                    HStack(spacing: 8) {
                        Text(s.removedForUndo(notice.kind)).font(LimenType.bodyMedium).foregroundStyle(colors.ink).frame(maxWidth: .infinity, alignment: .leading)
                        SmallKey(label: s.undo, tick: .confirm) { model.undo(notice.token) }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 6)
                    .padding(.vertical, 6)
                    .background(colors.plateRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .readable()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let notice = model.notice {
                    NoticeBar(text: notice).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.16), value: model.editingDefectId)
            .animation(.easeInOut(duration: 0.16), value: model.showDepositCompare)
            .animation(.easeInOut(duration: 0.16), value: model.undoNotice)
            .animation(.easeInOut(duration: 0.16), value: model.notice)
            .background(colors.plate.ignoresSafeArea())
            .environment(\.recordLocked, locked)
            .fullScreenCover(isPresented: Binding(get: { model.editingDefectId != nil }, set: { if !$0 { model.closeDefect() } })) {
                if let current = model.working, let id = model.editingDefectId {
                    DefectEditor(p: current, defectId: id).environment(\.recordLocked, current.isFinalized())
                }
            }
            .sheet(isPresented: Binding(get: { model.showDepositCompare }, set: { model.setDepositCompare($0) })) {
                DepositCompareOverlay()
            }
        }
    }
}

/// The flow's own masthead: the way out, where you are, the theme. No info mark: the sentence
/// per step it used to show went with Android 1.2.2, and nothing on a step explains the step.
private struct FlowMast: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let p: HandoverProtocol

    var body: some View {
        HStack(spacing: 6) {
            IconKey(glyph: .back, label: s.back) { model.flowBack() }
            LimenMark(size: 42)
            VStack(alignment: .leading, spacing: 0) {
                Text((p.kind == .entry ? s.entry : s.exit).uppercased()).font(LimenType.labelLarge).foregroundStyle(colors.ink)
                Text(p.address.ifBlank(s.noAddress)).font(LimenType.labelSmall).fixedSize(horizontal: false, vertical: true).foregroundStyle(colors.inkDim)
            }
            .padding(.leading, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            ThemeToggle(dark: model.darkTheme, description: s.themeMode) { model.toggleTheme() }
        }
    }
}

/// Says why nothing on this screen moves, and offers the one thing that does.
private struct SealBar: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s

    var body: some View {
        HStack(spacing: 4) {
            Text(s.lockedRecord.uppercased()).font(LimenType.mono(12)).foregroundStyle(colors.seal).frame(maxWidth: .infinity, alignment: .leading)
            InfoTip(tip: s.tipLocked())
            // Named for where it goes, not for what is done there. Amending is a deliberate act
            // with its own key on that step; a one-tap amendment on every screen would make a
            // stray thumb start a second record.
            SmallKey(label: s.stepExport.uppercased()) { model.goTo(.export) }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(colors.plateRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// One finding, one line: what it says, what hangs on it, and the way into the editor.
struct DefectLine: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let p: HandoverProtocol
    let d: Defect
    var showPlace = false

    var body: some View {
        var parts: [String] = []
        if showPlace {
            let place = p.defectPlace(d, s)
            if !place.isBlank { parts.append(place) }
        }
        if let item = p.defectItemLabel(d, s) { parts.append(item) }
        if !d.photos.isEmpty { parts.append("\(s.photos) \(d.photos.count)") }
        if d.chargedToTenant { parts.append(s.chargedToTenant) }
        if d.tenantResponse != .notStated { parts.append(s.tenantResponse(d.tenantResponse)) }
        let detail = parts.joined(separator: " · ")
        return Button {
            Haptics.play(.key)
            model.editDefect(d.id)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.text.ifBlank(s.defectText)).font(LimenType.bodyMedium).fixedSize(horizontal: false, vertical: true).foregroundStyle(colors.ink)
                    if !detail.isEmpty {
                        Text(detail).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward").foregroundStyle(colors.inkDim)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The handover's home. Three doors: the two halves of the handover, neither ahead of the other,
/// and the record itself, which is its review, its signatures and its export.
///
/// Only the closing is ordered, because a signature that saw no review is worth nothing.
/// Everything above it is entered in whatever order the handover itself takes.
struct HubStep: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    // Recomputed when the record changes, as Android's remember(p) does, not on every body pass:
    // the check stats every photograph and every signature file on disk.
    @State private var issues: [FinalizationIssue] = []
    @State private var showAllIssues = false

    var body: some View {
        let defects = p.defects.count
        let objectIssues = issues.filter { [.address, .place, .canton, .handoverDate, .handoverTime, .legalOverlay].contains($0) }
        ScrollView {
            VStack(spacing: 10) {
                if !objectIssues.isEmpty, !p.isFinalized() {
                    Panel(label: s.objectPreflight, warning: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let canton = p.objectCanton { CantonFlag(canton: canton, label: s.canton(canton), size: 30) }
                            SmallKey(label: s.completeObjectAndCanton, stretch: true) { model.goTo(.dossier) }
                        }
                    }
                }
                HubDoor(title: s.stepInspection, lead: s.hubInspectionLead, readout: [s.countRooms(p.rooms.count), s.countObjects(p.objects.count)].joined(separator: " · "), alert: defects > 0 ? s.countDefects(defects) : nil, glyph: .camera) {
                    model.goTo(.inspection)
                }
                HubDoor(title: s.stepDossier, lead: s.hubDossierLead, readout: s.countComponents(p.dossierCards().count), alert: nil, glyph: .edit) {
                    model.goTo(.dossier)
                }
                // A signed record has nothing left to close; what it still offers is its document.
                HubDoor(title: s.stepRecord, lead: s.hubRecordLead, readout: p.isFinalized() ? s.finalized : (p.isSigned() ? s.awaitingSignatures : s.notSigned), alert: nil, glyph: .confirm) {
                    model.goTo(locked ? .export : .review)
                }
                Spacer().frame(height: 2)
                // What is still missing, said here rather than found at the signature. Nothing is
                // blocked by it: Review is always reachable, and it repeats the same list. One
                // line at a time, the rest behind a count, as Android 1.2.1 lists them.
                if !issues.isEmpty {
                    Panel(label: s.stillMissing, warning: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(showAllIssues ? issues : Array(issues.prefix(1)), id: \.self) { issue in
                                CompletionIssueKey(p: p, issue: issue)
                            }
                            if issues.count > 1 {
                                SmallKey(label: "\(s.showAll) (\(issues.count))") { showAllIssues.toggle() }
                            }
                        }
                    }
                }
                Spacer().frame(height: 12)
            }
        }
        .onChange(of: p, initial: true) { _, now in issues = model.completionIssues(now) }
        .onChange(of: p.id) { _, _ in showAllIssues = false }
    }
}

/// One half of the handover, named, counted, and open at a touch.
private struct HubDoor: View {
    @Environment(\.limen) private var colors
    let title: String
    let lead: String
    let readout: String
    let alert: String?
    let glyph: ButtonGlyph
    let onPress: () -> Void

    var body: some View {
        KeySurface(radius: 14, fillColor: colors.plateRaised, outlineColor: colors.actionOutline, onPress: onPress) {
            HStack(spacing: 14) {
                Image(systemName: glyph.symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(colors.actionOutline).frame(width: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title.uppercased()).font(LimenType.doorTitle).tracking(0.4).foregroundStyle(colors.ink)
                    Text(lead).font(LimenType.labelSmall).foregroundStyle(colors.inkDim).multilineTextAlignment(.leading)
                    Spacer().frame(height: 6)
                    HStack(spacing: 8) {
                        Text(readout).font(LimenType.mono(13)).foregroundStyle(colors.inkDim)
                        if let alert { Text(alert).font(LimenType.mono(13, .bold)).foregroundStyle(colors.warningOutline) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward").foregroundStyle(colors.inkDim)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The two roads for the deposit, side by side with outbound links to current terms.
/// Deliberately neutral and deliberately shallow: provider identity and a link, nothing more.
/// The application always happens on the provider's own site; the app never recommends,
/// pre-fills or submits anything, which keeps it plainly outside insurance intermediation.
private struct Offer: Identifiable {
    let name: String
    let url: String
    var id: String { name }
}

private let bankOffers = [
    Offer(name: "UBS", url: "https://www.ubs.com/ch/de/services/accounts-and-cards/accounts/rental-surety-savings-account.html"),
    Offer(name: "BEKB", url: "https://www.bekb.ch"),
    Offer(name: "ZKB", url: "https://www.zkb.ch"),
]

private let insuranceOffers = [
    Offer(name: "AXA", url: "https://www.axa.ch/de/rechner/mietkaution.html"),
    Offer(name: "Helvetia", url: "https://www.helvetia.com/ch/web/de/privatkunden/versicherungen/mietkaution.html"),
    Offer(name: "goCaution", url: "https://www.gocaution.ch"),
    Offer(name: "SwissCaution", url: "https://www.swisscaution.ch"),
    Offer(name: "Firstcaution", url: "https://www.firstcaution.ch"),
    Offer(name: "SmartCaution", url: "https://www.smartcaution.ch"),
]

struct DepositCompareOverlay: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 18)
            HStack {
                Text(s.deposit).font(LimenType.titleMedium).foregroundStyle(colors.ink).frame(maxWidth: .infinity, alignment: .leading)
                InfoTip(tip: s.tipCompare())
            }
            Spacer().frame(height: 12)
            ScrollView {
                VStack(spacing: 10) {
                    Panel(label: s.currentTerms) {
                        Text(s.infoDeposit).font(LimenType.bodySmall).foregroundStyle(colors.inkDim)
                    }
                    Panel(label: s.depositBank) {
                        VStack(spacing: 6) { ForEach(bankOffers) { offer in OfferRow(offer: offer) } }
                    }
                    Panel(label: s.depositInsurance) {
                        VStack(spacing: 6) { ForEach(insuranceOffers) { offer in OfferRow(offer: offer) } }
                    }
                }
            }
            Spacer().frame(height: 10)
            SmallKey(label: s.done, stretch: true) { model.setDepositCompare(false) }
            Spacer().frame(height: 16)
        }
        .padding(.horizontal, 20)
        // The plate and the tap trap below stay on the full width; only the column is capped.
        // Capping the whole thing would have reopened the bug the next comment describes, with
        // the new side margins as the place taps fell through.
        .frame(maxWidth: readableMax)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // An opaque plate that also takes the touches, so a tap that misses a row never reaches
        // the masthead underneath.
        .background(colors.plate.ignoresSafeArea())
        .contentShape(Rectangle())
    }
}

private struct OfferRow: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.openURL) private var openURL
    let offer: Offer

    var body: some View {
        HStack {
            Text(offer.name).font(LimenType.bodyMedium).foregroundStyle(colors.ink).frame(maxWidth: .infinity, alignment: .leading)
            Chip(label: s.linkKey, dim: false) {
                if let url = URL(string: offer.url) {
                    openURL(url) { accepted in if !accepted { model.show(s.openLinkFailed) } }
                }
            }
        }
    }
}
