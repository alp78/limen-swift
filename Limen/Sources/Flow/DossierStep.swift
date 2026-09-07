import LimenKit
import SwiftUI

/// The paperwork half of a handover: the object, the people, and whichever of the money and
/// meter rubrics this particular handover actually has.
///
/// The three at the top are permanent, because a record without an address, a date and two named
/// parties is not a record. Everything below them is added on demand and printed only when added,
/// so a furnished sublet with no deposit and no meter of its own never has to look at a deposit
/// field, and its PDF never shows an empty one.
struct DossierStep: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    @State private var removing: DossierCard?
    @State private var confirmRemove = false

    private struct Section: Identifiable {
        let id: String
        let label: String
        let complete: Bool
    }

    var body: some View {
        let cards = p.dossierCards()
        let sections = [
            Section(id: "object", label: s.objectLabel, complete: objectSectionComplete(p)),
            Section(id: "parties", label: s.parties, complete: partiesSectionComplete(p)),
        ] + cards.map { Section(id: "card-\($0.rawValue)", label: s.dossierCard($0), complete: dossierSectionComplete(p, $0)) }
        let absent = DossierCard.allCases.filter { !cards.contains($0) }
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 10, pinnedViews: .sectionHeaders) {
                    SwiftUI.Section {
                        VStack(spacing: 10) {
                            ObjectCard(p: p)
                            LegalOverlayPanel(p: p)
                            HandoverDeadline(p: p)
                        }
                        .id("object")
                        PartiesCard(p: p).id("parties")
                        ForEach(cards, id: \.self) { card in
                            Group {
                                switch card {
                                case .contract: ContractCard(p: p) { ask(card) }
                                case .deposit: DepositCard(p: p) { ask(card) }
                                case .meters: MetersCard(p: p) { ask(card) }
                                case .keys: KeysCard(p: p) { ask(card) }
                                case .notes: NotesCard(p: p) { ask(card) }
                                }
                            }
                            .id("card-\(card.rawValue)")
                        }
                        if !absent.isEmpty, !locked {
                            Panel(label: s.addComponent) {
                                FlowRow(spacing: 6) {
                                    ForEach(absent, id: \.self) { card in
                                        Chip(label: "+ \(s.dossierCard(card))", dim: false) { model.addDossierCard(card) }
                                    }
                                }
                            }
                        }
                        BigKey(label: locked ? s.stepExport.uppercased() : s.hubClose) { model.goTo(locked ? .export : .review) }
                        Spacer().frame(height: 12)
                    } header: {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(sections) { section in
                                    Chip(label: "\(section.complete ? "✓" : "○") \(section.label)") {
                                        withAnimation { reader.scrollTo(section.id, anchor: .top) }
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .background(colors.plate)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .confirmDialog($confirmRemove, body: s.removeComponentBody) {
            if let removing { model.removeDossierCard(removing) }
            removing = nil
        }
    }

    private func ask(_ card: DossierCard) {
        removing = card
        confirmRemove = true
    }
}

private func objectSectionComplete(_ p: HandoverProtocol) -> Bool {
    !p.address.isBlank && !p.place.isBlank && p.objectCanton != nil && !p.handoverDate.isBlank && !p.handoverTime.isBlank &&
        (p.resolvedLegalOverlay()?.isComplete(p.legalOverlay) == true)
}

private func partiesSectionComplete(_ p: HandoverProtocol) -> Bool {
    [Role.tenant, .landlord].allSatisfy { role in !(p.parties.first { $0.role == role }?.name.isBlank ?? true) }
}

private func dossierSectionComplete(_ p: HandoverProtocol, _ card: DossierCard) -> Bool {
    switch card {
    case .contract: return p.contract != Contract()
    case .deposit:
        switch p.deposit.kind {
        case .none: return false
        case .bankAccount: return [p.deposit.amountChf, p.deposit.bank, p.deposit.account].allSatisfy { !$0.isBlank }
        case .insurance: return [p.deposit.amountChf, p.deposit.provider, p.deposit.policyNo].allSatisfy { !$0.isBlank }
        }
    case .meters: return !p.meters.isBlank
    // The same rule the finalization gate applies, so a ticked chip cannot sit beside a blocked
    // FINALIZE with nothing on screen naming what is missing.
    case .keys: return CompletionRules.keyOutcomeRecorded(p)
    case .notes: return !p.remarks.isBlank || !p.chargesStatementBy.isBlank
    }
}

/// The removal affordance every optional component carries, in the same place on each. An icon
/// rather than a word: a component's own fields are what the eye should reach first.
private struct CardHeader: View {
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let onRemove: () -> Void

    var body: some View {
        if !locked {
            HStack {
                Spacer()
                IconKey(glyph: .delete, label: s.delete, destructive: true, onPress: onRemove)
            }
        }
    }
}

// MARK: The object

private struct ObjectCard: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let p: HandoverProtocol
    @State private var searching = false
    @State private var matches: [SwissAddressCandidate] = []
    @State private var focused: Set<String> = []
    @State private var verified = false
    @State private var loadedFor = ""

    private struct LookupKey: Equatable {
        let id: String
        let query: String
        let anyFocus: Bool
        let verified: Bool
    }

    var body: some View {
        let anyFocus = !focused.isEmpty
        let query = [p.address, p.place].filter { !$0.isBlank }.joined(separator: " ")
        Panel(label: s.objectLabel, info: s.tipAddress()) {
            VStack(alignment: .leading, spacing: 8) {
                // Above the fields they fill: below them, the keyboard covered the answer.
                if anyFocus, !verified, searching {
                    Text(s.addressSearching).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                }
                if anyFocus, !verified {
                    AddressMatchList(matches: matches) { candidate in
                        model.edit { current in
                            let moved = current.objectCanton != candidate.canton
                            var next = current
                            next.address = [candidate.street, candidate.flatNumber].filter { !$0.isBlank }.joined(separator: " ")
                            next.place = [candidate.postalCode, candidate.city].filter { !$0.isBlank }.joined(separator: " ")
                            next.objectCanton = candidate.canton
                            // Re-picking the same address must not discard answers already given for it.
                            if moved {
                                next.romandFrameworkInLease = false
                                next.legalOverlay = LegalOverlayRecord()
                            }
                            return next
                        }
                        matches = []
                        verified = true
                    }
                }
                Field(label: s.address, value: p.address, onFocusChanged: { setFocused("address", $0) }) { value in
                    editAddress { var x = $0; x.address = value; return x }
                }
                Field(label: s.place, value: p.place, onFocusChanged: { setFocused("place", $0) }) { value in
                    editAddress { var x = $0; x.place = value; return x }
                }
                CantonPicker(selected: p.objectCanton) { canton in
                    model.edit { current in
                        if current.objectCanton == canton { return current }
                        var next = current
                        next.objectCanton = canton
                        next.romandFrameworkInLease = false
                        next.legalOverlay = LegalOverlayRecord()
                        return next
                    }
                }
                Field(label: s.objectDetail, value: p.objectDetail) { value in model.edit { var x = $0; x.objectDetail = value; return x } }
                DateAndTimeRow(dateLabel: s.handoverDate, date: p.handoverDate, timeLabel: s.handoverTime, time: p.handoverTime, onDate: { value in
                    model.edit { current in
                        var next = current
                        next.handoverDate = value
                        if current.handoverDate != value { next.legalOverlay = LegalOverlayRecord() }
                        return next
                    }
                }, onTime: { value in model.edit { var x = $0; x.handoverTime = value; return x } })
                DateField(label: s.lastProtocol, stored: p.lastProtocolDate) { value in model.edit { var x = $0; x.lastProtocolDate = value; return x } }
            }
        }
        .onChange(of: p.id, initial: true) { _, id in
            guard loadedFor != id else { return }
            loadedFor = id
            verified = !p.address.isBlank && !p.place.isBlank && p.objectCanton != nil
            matches = []
            focused = []
        }
        .task(id: LookupKey(id: p.id, query: query, anyFocus: anyFocus, verified: verified)) {
            if !anyFocus || verified || query.trimmingCharacters(in: .whitespaces).count < 3 {
                matches = []
                searching = false
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            searching = true
            let found = await SwissAddressLookup.search(query)
            if Task.isCancelled { return }
            matches = found
            searching = false
        }
    }

    private func setFocused(_ field: String, _ isFocused: Bool) {
        if isFocused { focused.insert(field) } else { focused.remove(field) }
    }

    // Typing a street name does NOT clear the canton or the cantonal answers. The canton changes
    // where the canton is chosen: the picker and the candidate list, both of which reset the
    // answers only when the canton itself actually moves.
    private func editAddress(_ transform: (HandoverProtocol) -> HandoverProtocol) {
        verified = false
        matches = []
        searching = false
        model.edit(transform)
    }
}

/// Legal timing is shown where the handover date is entered, not as a detached utility. Both
/// kinds state their deadline as the date itself, computed from the handover, with the reasoning
/// and the article behind the mark. A date is what a person acts on; the paragraph is read once.
private struct HandoverDeadline: View {
    @Environment(\.str) private var s
    let p: HandoverProtocol

    var body: some View {
        if let handover = SwissDate.parse(p.handoverDate) {
            if p.kind == .entry {
                Panel(label: s.clockEntryTitle, info: s.tipEntryNotice()) {
                    Deadline(label: s.listBy, date: Clocks.entryListBy(handover))
                }
            } else {
                Panel(label: s.clockExitTitle, info: s.tipExitNotice()) {
                    HStack(alignment: .top, spacing: 16) {
                        Deadline(label: s.safeBy, date: Clocks.exitNoticeSafeBy(handover)).frame(maxWidth: .infinity, alignment: .leading)
                        Deadline(label: s.latestBy, date: Clocks.exitNoticeLatest(handover)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// One computed date, read the way it is written on a form.
private struct Deadline: View {
    @Environment(\.limen) private var colors
    let label: String
    let date: LocalDate

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
            Text(SwissDate.display(date.isoString)).font(LimenType.mono(22, like: .title2)).foregroundStyle(colors.ink)
        }
    }
}

// MARK: The people

private struct PartiesCard: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol

    var body: some View {
        Panel(label: s.parties) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(p.parties.enumerated()), id: \.offset) { index, party in
                    // The two mandatory roles are always there and need no announcing; a role
                    // that a key just added does.
                    if index < 2 {
                        PartyBlock(p: p, index: index, party: party)
                    } else {
                        Revealed(key: party.role) { PartyBlock(p: p, index: index, party: party) }
                    }
                }
                if !locked {
                    HStack(spacing: 6) {
                        ForEach([Role.witness, .expert, .nextTenant], id: \.self) { role in
                            if !p.parties.contains(where: { $0.role == role }) {
                                SmallKey(label: "+ \(s.role(role))", stretch: true) {
                                    model.edit { var x = $0; x.parties.append(Party(role)); return x }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct PartyBlock: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    let index: Int
    let party: Party

    private func update(_ change: @escaping (inout Party, String) -> Void) -> (String) -> Void {
        { value in
            model.edit { current in
                var next = current
                guard index < next.parties.count else { return current }
                change(&next.parties[index], value)
                return next
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(s.role(party.role).uppercased()).font(LimenType.labelSmall).foregroundStyle(colors.inkDim).frame(maxWidth: .infinity, alignment: .leading)
                let removable = [Role.witness, .expert, .nextTenant].contains(party.role)
                if removable, !locked {
                    IconKey(glyph: .delete, label: s.delete, destructive: true) {
                        model.edit { current in
                            var next = current
                            next.parties = current.parties.enumerated().filter { $0.offset != index }.map(\.element)
                            return next
                        }
                    }
                }
            }
            Field(label: s.role(party.role), value: party.name, onChange: update { $0.name = $1 })
            if party.role == .landlord || party.role == .tenant {
                Field(label: s.representedBy, value: party.representedBy, onChange: update { $0.representedBy = $1 })
            }
            if party.role == .tenant, p.kind == .exit {
                Field(label: s.newAddress, value: party.address, onChange: update { $0.address = $1 })
            }
            HStack(alignment: .top, spacing: 8) {
                Field(label: s.phoneNumber, value: party.phone, keyboard: .phonePad, onChange: update { $0.phone = $1 })
                Field(label: s.email, value: party.email, keyboard: .emailAddress, onChange: update { $0.email = $1 })
            }
        }
    }
}

// MARK: The optional components

private struct ContractCard: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    let p: HandoverProtocol
    let onRemove: () -> Void

    var body: some View {
        Panel(label: s.contract) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(onRemove: onRemove)
                HStack(alignment: .top, spacing: 8) {
                    Field(label: s.monthlyRent, value: p.contract.monthlyRentChf, keyboard: .decimalPad) { v in model.edit { var x = $0; x.contract.monthlyRentChf = v; return x } }
                    Field(label: s.serviceCharges, value: p.contract.serviceChargesChf, keyboard: .decimalPad) { v in model.edit { var x = $0; x.contract.serviceChargesChf = v; return x } }
                }
                DateField(label: s.leaseConcludedOn, stored: p.contract.conclusionDate) { v in
                    model.edit { record in
                        var next = record
                        next.contract.conclusionDate = v
                        if record.contract.conclusionDate != v { next.legalOverlay = LegalOverlayRecord() }
                        return next
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    DateField(label: s.tenancyStart, stored: p.contract.startDate) { v in model.edit { var x = $0; x.contract.startDate = v; return x } }
                    DateField(label: s.tenancyEnd, stored: p.contract.endDate) { v in model.edit { var x = $0; x.contract.endDate = v; return x } }
                }
                DateField(label: s.noticeDate, stored: p.contract.noticeDate) { v in model.edit { var x = $0; x.contract.noticeDate = v; return x } }
            }
        }
    }
}

private struct DepositCard: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    let onRemove: () -> Void

    var body: some View {
        Panel(label: s.deposit, info: s.tipDeposit()) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(onRemove: onRemove)
                PillRow(options: DepositKind.allCases.map { ($0, s.depositKind($0)) }, current: p.deposit.kind, enabled: !locked) { k in
                    model.edit { var x = $0; x.deposit.kind = k; return x }
                }
                // Whichever road the pill above chose, its fields arrive under the highlight.
                if p.deposit.kind != .none {
                    Revealed(key: p.deposit.kind) {
                        VStack(alignment: .leading, spacing: 8) {
                            if p.deposit.kind == .insurance {
                                CautionProviderPicker(storedName: p.deposit.provider) { provider in
                                    model.edit { current in
                                        let existing = current.deposit.provider
                                        let name = provider.storedName ?? (CautionProvider.fromStoredName(existing) == .other ? existing : "")
                                        var next = current
                                        next.deposit.provider = name
                                        return next
                                    }
                                }
                                if CautionProvider.fromStoredName(p.deposit.provider) == .other {
                                    Field(label: s.otherCautionProvider, value: p.deposit.provider) { v in model.edit { var x = $0; x.deposit.provider = v; return x } }
                                }
                                HStack(alignment: .top, spacing: 8) {
                                    Field(label: s.depositPolicy, value: p.deposit.policyNo) { v in model.edit { var x = $0; x.deposit.policyNo = v; return x } }.layoutPriority(1.3)
                                    Field(label: s.depositAmount, value: p.deposit.amountChf, keyboard: .decimalPad) { v in model.edit { var x = $0; x.deposit.amountChf = v; return x } }
                                }
                            } else {
                                Field(label: s.depositBankName, value: p.deposit.bank) { v in model.edit { var x = $0; x.deposit.bank = v; return x } }
                                HStack(alignment: .top, spacing: 8) {
                                    Field(label: s.depositAccount, value: p.deposit.account) { v in model.edit { var x = $0; x.deposit.account = v; return x } }.layoutPriority(1.3)
                                    Field(label: s.depositAmount, value: p.deposit.amountChf, keyboard: .decimalPad) { v in model.edit { var x = $0; x.deposit.amountChf = v; return x } }
                                }
                            }
                        }
                    }
                }
                // Only at entry: the deposit is chosen before moving in. At exit it already exists
                // and the card merely documents it for the release instruction.
                if p.kind == .entry {
                    HStack {
                        SmallKey(label: s.compareKey, stretch: true) { model.setDepositCompare(true) }
                        InfoTip(tip: s.tipCompare())
                    }
                }
            }
        }
    }
}

private struct MetersCard: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    let p: HandoverProtocol
    let onRemove: () -> Void

    var body: some View {
        Panel(label: s.meters) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(onRemove: onRemove)
                HStack(alignment: .top, spacing: 8) {
                    Field(label: s.meterElec1, value: p.meters.electricity1, keyboard: .decimalPad) { v in model.edit { var x = $0; x.meters.electricity1 = v; return x } }
                    Field(label: s.meterElec2, value: p.meters.electricity2, keyboard: .decimalPad) { v in model.edit { var x = $0; x.meters.electricity2 = v; return x } }
                }
                HStack(alignment: .top, spacing: 8) {
                    Field(label: s.meterGas, value: p.meters.gas, keyboard: .decimalPad) { v in model.edit { var x = $0; x.meters.gas = v; return x } }
                    Field(label: s.meterWater, value: p.meters.water, keyboard: .decimalPad) { v in model.edit { var x = $0; x.meters.water = v; return x } }
                }
                HStack(alignment: .top, spacing: 8) {
                    Field(label: s.meterHotWater, value: p.meters.hotWater, keyboard: .decimalPad) { v in model.edit { var x = $0; x.meters.hotWater = v; return x } }
                    Field(label: s.meterOil, value: p.meters.heatingOil, keyboard: .decimalPad) { v in model.edit { var x = $0; x.meters.heatingOil = v; return x } }
                }
            }
        }
    }
}

private struct KeysCard: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol
    let onRemove: () -> Void
    @State private var adding = false
    @State private var otherLabel = ""

    var body: some View {
        Panel(label: s.keysLabel) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(onRemove: onRemove)
                Text(s.keyTransferLabel).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                PillRow(options: KeyTransferStatus.allCases.map { ($0, s.keyTransfer($0)) }, current: p.keyTransfer, enabled: !locked) { status in
                    // "No physical keys" zeroes every count the operator already entered, so it is
                    // the one pill that goes through the undo bar rather than a plain edit.
                    let transform: (HandoverProtocol) -> HandoverProtocol = { record in
                        var next = record
                        if status == .noPhysicalKeys {
                            next.keyTransfer = status
                            next.keyTransferNote = ""
                            next.keys = record.keys.map { var k = $0; k.count = 0; return k }
                            next.rooms = record.rooms.map { var r = $0; r.keysCount = 0; return r }
                            next.selfMadeKeys = false
                        } else {
                            next.keyTransfer = status
                            next.keyTransferNote = status == .incomplete ? record.keyTransferNote : ""
                        }
                        return next
                    }
                    if status == .noPhysicalKeys { model.editUndoably(transform) } else { model.edit(transform) }
                }
                if p.keyTransfer == .incomplete {
                    Field(label: s.keyTransferNote, value: p.keyTransferNote, singleLine: false) { note in model.edit { var x = $0; x.keyTransferNote = note; return x } }
                }
                if p.keyTransfer != .noPhysicalKeys {
                    ForEach(Array(p.keys.enumerated()), id: \.offset) { i, key in
                        HStack {
                            Text(key.kind == .other && !key.label.isBlank ? key.label : s.keyKind(key.kind)).font(LimenType.bodyMedium).foregroundStyle(colors.ink).frame(maxWidth: .infinity, alignment: .leading)
                            if locked {
                                Text(String(key.count)).font(LimenType.mono(17)).foregroundStyle(colors.ink)
                            } else {
                                Stepper(count: key.count) { c in
                                    model.edit { current in
                                        var next = current
                                        if i < next.keys.count { next.keys[i].count = c }
                                        return next
                                    }
                                }
                                Spacer().frame(width: 6)
                                IconKey(glyph: .delete, label: s.delete, destructive: true) {
                                    model.edit { current in
                                        var next = current
                                        next.keys = current.keys.enumerated().filter { $0.offset != i }.map(\.element)
                                        return next
                                    }
                                }
                            }
                        }
                    }
                    if !locked { SmallKey(label: s.addKeyKind, stretch: true) { adding.toggle() } }
                    if adding, !locked {
                        VStack(alignment: .leading, spacing: 8) {
                            FlowRow(spacing: 6) {
                                ForEach(KeyKind.allCases.filter { $0 != .other }, id: \.self) { kind in
                                    Chip(label: "+ \(s.keyKind(kind))", dim: false) {
                                        model.edit { var x = $0; x.keys.append(KeyCount(kind)); return x }
                                        adding = false
                                    }
                                }
                            }
                            // A key the canon has no word for: the bike shed, the laundry, the gate code fob.
                            HStack(alignment: .top, spacing: 8) {
                                Field(label: s.keyLabel, value: otherLabel) { otherLabel = $0 }
                                SmallKey(label: s.add, enabled: !otherLabel.trimmingCharacters(in: .whitespaces).isEmpty) {
                                    model.edit { var x = $0; x.keys.append(KeyCount(.other, label: otherLabel.trimmingCharacters(in: .whitespaces))); return x }
                                    otherLabel = ""
                                    adding = false
                                }
                            }
                        }
                    }
                    Toggle(label: s.selfMadeKeys, on: p.selfMadeKeys, enabled: !locked) {
                        model.edit { var x = $0; x.selfMadeKeys.toggle(); return x }
                    }
                }
            }
        }
    }
}

private struct NotesCard: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.str) private var s
    let p: HandoverProtocol
    let onRemove: () -> Void

    var body: some View {
        Panel(label: s.notes) {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(onRemove: onRemove)
                Field(label: s.remarks, value: p.remarks, singleLine: false) { v in model.edit { var x = $0; x.remarks = v; return x } }
                // A date, and typed as one: the label has always said "by", in every language.
                DateField(label: s.chargesBy, stored: p.chargesStatementBy) { v in model.edit { var x = $0; x.chargesStatementBy = v; return x } }
            }
        }
    }
}

private struct CautionProviderPicker: View {
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    let storedName: String
    let onSelect: (CautionProvider) -> Void

    var body: some View {
        let selected = CautionProvider.fromStoredName(storedName)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        Menu {
            ForEach(CautionProvider.allCases, id: \.self) { provider in
                Button {
                    Haptics.play(.key)
                    onSelect(provider)
                } label: {
                    if provider == selected {
                        Label(s.cautionProvider(provider), systemImage: "checkmark")
                    } else {
                        Text(s.cautionProvider(provider))
                    }
                }
                .disabled(provider == selected)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.depositProvider).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                    Text(s.cautionProvider(selected)).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").foregroundStyle(colors.inkDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(colors.input, in: shape)
            .overlay(shape.strokeBorder(colors.plateEdge, lineWidth: 1))
        }
        .accessibilityLabel(s.depositProvider)
    }
}

/// The dated canton layer, kept beside the object facts that select it.
struct LegalOverlayPanel: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.limen) private var colors
    @Environment(\.str) private var s
    @Environment(\.recordLocked) private var locked
    let p: HandoverProtocol

    var body: some View {
        if let overlay = p.resolvedLegalOverlay() {
            let complete = overlay.isComplete(p.legalOverlay)
            let needsNote = overlay.requirements.contains { requirement in
                let status = p.legalOverlay.status(requirement)
                return status != nil && status != .confirmed
            }
            Panel(label: s.legalOverlayTitle, info: s.tipLegalOverlay(), warning: !complete) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        CantonFlag(canton: overlay.canton, size: 34)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.canton(overlay.canton)).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                            Text("\(s.legalBasis): \(s.legalProfile(overlay.profile))").font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if p.kind == .entry {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.initialRentForm).font(LimenType.labelSmall).foregroundStyle(colors.inkDim)
                            Text(s.initialRentFormRule(overlay.initialRentFormRule)).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                        }
                        if overlay.profile.isVaudRulv {
                            Text(s.vaudPreviousExitReport).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                        }
                    }
                    if overlay.canton.supportsRomandFramework, !overlay.profile.isVaudRulv {
                        Toggle(label: s.romandFrameworkInLease, on: p.romandFrameworkInLease, enabled: !locked) {
                            model.edit { var x = $0; x.romandFrameworkInLease.toggle(); return x }
                        }
                    }
                    ForEach(overlay.requirements, id: \.self) { requirement in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(s.legalRequirement(requirement)).font(LimenType.bodyMedium).foregroundStyle(colors.ink)
                            FlowRow(spacing: 6) {
                                ForEach(LegalCheckStatus.allCases, id: \.self) { status in
                                    let selected = p.legalOverlay.status(requirement) == status
                                    Chip(label: s.legalCheckStatus(status), active: selected, tick: status == .confirmed ? .confirm : .key, enabled: !locked, destructive: status == .missingOrDisputed, selectionState: selected) {
                                        model.edit { var x = $0; x.legalOverlay = $0.legalOverlay.withStatus(requirement, status); return x }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    Field(label: s.legalOverlayNote, value: p.legalOverlay.note, singleLine: false, hint: needsNote && p.legalOverlay.note.isBlank ? s.legalOverlayNoteRequired : nil, isError: needsNote && p.legalOverlay.note.isBlank) { note in
                        model.edit { var x = $0; x.legalOverlay.note = note; return x }
                    }
                }
            }
        }
    }
}
