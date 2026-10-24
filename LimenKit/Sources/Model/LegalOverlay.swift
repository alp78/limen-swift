import Foundation

public let legalRuleSetId = "ch-tenancy-2026.2"
public let legalSourcesCheckedOn = "2026-10-14"

/// A dated legal/practice check that is recorded with the handover.
public enum LegalRequirement: String, CaseIterable, Hashable, Sendable {
    case leaseAndLocalTiming = "LeaseAndLocalTiming"
    case initialRentForm = "InitialRentForm"
    case depositProof = "DepositProof"
    case tenantLiabilityInsurance = "TenantLiabilityInsurance"
    case landlordLiabilityInsurance = "LandlordLiabilityInsurance"
    case vaudExitReadiness = "VaudExitReadiness"
    case cantonalDepositHandling = "CantonalDepositHandling"

    public var ordinal: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// Missing or disputed items remain recordable, but require an explanatory note.
public enum LegalCheckStatus: String, CaseIterable, Hashable, Sendable {
    case confirmed = "Confirmed"
    case missingOrDisputed = "MissingOrDisputed"
    case notApplicable = "NotApplicable"
    case toVerify = "ToVerify"
}

/// The operator's recorded outcome for the checks selected by the dated overlay.
///
/// A map keeps the file forward-compatible: adding a future canton rule does not alter older
/// records, and changing canton or handover date can reset this whole small record safely.
public struct LegalOverlayRecord: Hashable, Sendable {
    public var checks = OrderedMap<LegalRequirement, LegalCheckStatus>()
    public var note: String = ""
    public var ruleSetId: String = ""
    public var notes = OrderedMap<LegalRequirement, String>()

    public init() {}

    public func status(_ requirement: LegalRequirement) -> LegalCheckStatus? { checks[requirement] }

    public func withStatus(_ requirement: LegalRequirement, _ status: LegalCheckStatus) -> LegalOverlayRecord {
        var copy = self
        copy.checks[requirement] = status
        copy.ruleSetId = legalRuleSetId
        return copy
    }

    public func withoutStatus(_ requirement: LegalRequirement) -> LegalOverlayRecord {
        var copy = self
        copy.checks[requirement] = nil
        return copy
    }
}

/// What the official initial-rent form snapshot says for the selected object and date.
public enum InitialRentFormRule: String, CaseIterable, Hashable, Sendable {
    case required = "Required"
    case conditionalLocal = "ConditionalLocal"
    case notRequired = "NotRequired"
    case verifyCurrent = "VerifyCurrent"
}

/// The effective, role-neutral layer placed on top of the common Swiss handover flow.
public struct ResolvedLegalOverlay: Hashable, Sendable {
    public var canton: SwissCanton
    public var handoverDate: LocalDate
    public var initialRentReferenceDate: LocalDate?
    public var profile: LegalProfile
    public var initialRentFormRule: InitialRentFormRule
    public var requirements: [LegalRequirement]
    public var ruleSetId: String = legalRuleSetId

    public func needsExplanation(_ requirement: LegalRequirement, record: LegalOverlayRecord) -> Bool {
        record.status(requirement) != .confirmed ||
            (requirement == .initialRentForm && [.verifyCurrent, .conditionalLocal].contains(initialRentFormRule))
    }

    public func isComplete(_ record: LegalOverlayRecord) -> Bool {
        if record.ruleSetId != ruleSetId { return false }
        if requirements.contains(where: { record.status($0) == nil }) { return false }
        if [.verifyCurrent, .conditionalLocal].contains(initialRentFormRule), record.status(.initialRentForm) == .confirmed,
           (record.notes[.initialRentForm] ?? "").isBlank,
           !(record.ruleSetId == "ch-tenancy-2026.1" && !record.note.isBlank) { return false }
        return requirements.allSatisfy {
            record.status($0) == .confirmed || !(record.notes[$0] ?? "").isBlank ||
                (record.ruleSetId == "ch-tenancy-2026.1" && !record.note.isBlank)
        }
    }
}

private let fullInitialRentFormCantons2026: Set<SwissCanton> = [.be, .bs, .fr, .ge, .lu, .zg, .zh]

public let vaudDistricts = ["Aigle", "Broye-Vully", "Gros-de-Vaud", "Jura-Nord vaudois", "Lausanne",
                           "Lavaux-Oron", "Morges", "Nyon", "Ouest lausannois", "Riviera-Pays-d’Enhaut"]

/// Legal dwelling category, independent of the rooms selected for inspection. NE 224.2 art. 2
/// connects the initial-rent form duty to the LVAL list; 846.02 art. 2 excludes half rooms.
public func neInitialRentRule(municipality: String, rooms: String) -> InitialRentFormRule {
    guard let count = Double(rooms.replacingOccurrences(of: ",", with: ".")), count.isFinite, count > 0,
          count < Double(Int.max) else { return .conditionalLocal }
    let locality = municipality.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    let range: ClosedRange<Int>
    switch locality {
    case "latena": range = 4...5
    case "la grande beroche": range = 3...5
    case "neuchatel", "cornaux", "cressier", "le landeron", "boudry", "cortaillod", "milvignes", "rochefort", "val-de-ruz": range = 2...5
    default: return .conditionalLocal
    }
    return range.contains(Int(count)) ? .required : .notRequired
}

extension HandoverProtocol {
    public func resolvedLegalOverlay() -> ResolvedLegalOverlay? {
        guard let canton = objectCanton, let date = LocalDate.parse(handoverDate) else { return nil }
        let reference = LocalDate.parse(contract.conclusionDate)
        let profile = legalProfile()
        if let snapshot = details.legalSnapshot {
            // Preserve the frozen classification. Unknown enum names cannot be guessed.
            guard let frozenProfile = LegalProfile(rawValue: snapshot.profile),
                  let frozenRule = InitialRentFormRule(rawValue: snapshot.initialRentFormRule) else { return nil }
            return ResolvedLegalOverlay(canton: canton, handoverDate: date, initialRentReferenceDate: reference,
                                        profile: frozenProfile, initialRentFormRule: frozenRule,
                                        requirements: snapshot.requirements, ruleSetId: snapshot.ruleSetId)
        }
        let historicRule: InitialRentFormRule = reference?.year != 2026 ? .verifyCurrent :
            fullInitialRentFormCantons2026.contains(canton) ? .required :
            [SwissCanton.ne, .vd].contains(canton) ? .conditionalLocal : .notRequired
        if isFinalized() {
            let requirements = legalOverlay.ruleSetId == "ch-tenancy-2026.1"
                ? legalRequirements(profile: profile, initialRule: historicRule, canton: canton, legacy: true)
                : legalOverlay.checks.keys.sorted { $0.ordinal < $1.ordinal }
            return ResolvedLegalOverlay(canton: canton, handoverDate: date, initialRentReferenceDate: reference,
                                        profile: profile, initialRentFormRule: historicRule, requirements: requirements,
                                        ruleSetId: legalOverlay.ruleSetId.ifBlank("legacy-unversioned"))
        }
        var rule = historicRule
        if reference?.year == 2026 {
            if canton == .ne { rule = neInitialRentRule(municipality: details.municipality, rooms: details.habitableRooms) }
            if canton == .vd {
                rule = details.district == "Aigle" ? .notRequired : vaudDistricts.contains(details.district) ? .required : .conditionalLocal
            }
        }
        return ResolvedLegalOverlay(canton: canton, handoverDate: date, initialRentReferenceDate: reference,
                                    profile: profile, initialRentFormRule: rule,
                                    requirements: legalRequirements(profile: profile, initialRule: rule, canton: canton, legacy: false))
    }

    private func legalRequirements(profile: LegalProfile, initialRule: InitialRentFormRule, canton: SwissCanton, legacy: Bool) -> [LegalRequirement] {
        var requirements: [LegalRequirement] = [.leaseAndLocalTiming]
        if !legacy, deposit.kind != .none, [SwissCanton.fr, .ge, .ti].contains(canton) { requirements.append(.cantonalDepositHandling) }
        if kind == .entry, initialRule != .notRequired { requirements.append(.initialRentForm) }
        if profile.isVaudRulv {
            if kind == .entry {
                if deposit.kind != .none { requirements.append(.depositProof) }
                requirements += [.tenantLiabilityInsurance, .landlordLiabilityInsurance]
            } else { requirements.append(.vaudExitReadiness) }
        }
        return requirements
    }

    public func freezeLegalRules() -> LegalSnapshot? {
        if let snapshot = details.legalSnapshot { return snapshot }
        // A historic final without a retained snapshot has no dated source list to recover.
        // Showing today's sources as its frozen provenance would invent historical evidence.
        guard !isFinalized() else { return nil }
        guard let overlay = resolvedLegalOverlay() else { return nil }
        return LegalSnapshot(ruleSetId: overlay.ruleSetId, profile: overlay.profile.rawValue,
                             initialRentFormRule: overlay.initialRentFormRule.rawValue,
                             requirements: overlay.requirements, sources: legalSources(canton: objectCanton),
                             checkedOn: legalSourcesCheckedOn)
    }

    /// Only inputs that affect a check remove its answer; retained notes explain the prior review.
    /// The street and the place are not among them: no requirement resolves from their text, the
    /// canton is chosen apart from them, and a keystroke in either used to empty every answer
    /// with no undo.
    public func invalidatedLegalRequirements(next: HandoverProtocol) -> Set<LegalRequirement> {
        if objectCanton != next.objectCanton { return Set(LegalRequirement.allCases) }
        var changed = Set<LegalRequirement>()
        if handoverDate != next.handoverDate || contract.startDate != next.contract.startDate || contract.endDate != next.contract.endDate {
            changed.formUnion([.leaseAndLocalTiming, .depositProof, .tenantLiabilityInsurance, .landlordLiabilityInsurance, .vaudExitReadiness])
        }
        if contract.conclusionDate != next.contract.conclusionDate { changed.formUnion([.initialRentForm, .depositProof, .leaseAndLocalTiming]) }
        if deposit != next.deposit { changed.formUnion([.depositProof, .cantonalDepositHandling]) }
        if details.municipality != next.details.municipality || details.district != next.details.district { changed.formUnion([.initialRentForm, .leaseAndLocalTiming]) }
        if details.habitableRooms != next.details.habitableRooms { changed.insert(.initialRentForm) }
        if romandFrameworkInLease != next.romandFrameworkInLease || details.actualTransferDate != next.details.actualTransferDate ||
            details.notificationClause != next.details.notificationClause || details.notificationDays != next.details.notificationDays { changed.insert(.leaseAndLocalTiming) }
        return changed
    }
}

public let conciliationDirectory = "https://www.bwo.admin.ch/dam/de/sd-web/tzHM7tFgxwhW/20260114_Schlichtungsbeh%C3%B6rden.pdf"

public func legalSources(canton: SwissCanton?) -> [String] {
    var sources = ["https://www.fedlex.admin.ch/eli/cc/27/317_321_377/fr",
                   "https://www.bwo.admin.ch/fr/formule-officielle-loyer-initial", conciliationDirectory]
    switch canton {
    case .vd: sources += ["https://www.vd.ch/territoire-et-construction/logement/droit-du-bail", "https://www.vd.ch/territoire-et-construction/logement/politique-du-logement/penurie-de-logements"]
    case .ne: sources += ["https://rsn.ne.ch/DATA/program/books/rsne/htm/224.1.htm", "https://rsn.ne.ch/DATA/program/books/rsne/htm/224.2.htm", "https://rsn.ne.ch/DATA/program/books/rsne/htm/846.02.htm"]
    case .fr: sources.append("https://bdlf.fr.ch/app/fr/texts_of_law/222.3.1")
    case .ge: sources.append("https://silgeneve.ch/legis/data/rsg_i4_10.htm")
    case .ti: sources.append("https://www3.ti.ch/CAN/RLeggi/public/index.php/raccolta-leggi/legge/num/153")
    default: break
    }
    return sources
}
