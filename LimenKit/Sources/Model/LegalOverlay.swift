import Foundation

public let legalRuleSetId = "ch-tenancy-2026.1"

/// A dated legal/practice check that is recorded with the handover.
public enum LegalRequirement: String, CaseIterable, Hashable, Sendable {
    case leaseAndLocalTiming = "LeaseAndLocalTiming"
    case initialRentForm = "InitialRentForm"
    case depositProof = "DepositProof"
    case tenantLiabilityInsurance = "TenantLiabilityInsurance"
    case landlordLiabilityInsurance = "LandlordLiabilityInsurance"
    case vaudExitReadiness = "VaudExitReadiness"

    public var ordinal: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// Missing or disputed items remain recordable, but require an explanatory note.
public enum LegalCheckStatus: String, CaseIterable, Hashable, Sendable {
    case confirmed = "Confirmed"
    case missingOrDisputed = "MissingOrDisputed"
    case notApplicable = "NotApplicable"
}

/// The operator's recorded outcome for the checks selected by the dated overlay.
///
/// A map keeps the file forward-compatible: adding a future canton rule does not alter older
/// records, and changing canton or handover date can reset this whole small record safely.
public struct LegalOverlayRecord: Hashable, Sendable {
    public var checks = OrderedMap<LegalRequirement, LegalCheckStatus>()
    public var note: String = ""
    public var ruleSetId: String = ""

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

    public func isComplete(_ record: LegalOverlayRecord) -> Bool {
        if record.ruleSetId != ruleSetId { return false }
        if requirements.contains(where: { record.status($0) == nil }) { return false }
        let needsExplanation = requirements.contains { record.status($0) != .confirmed }
        return !needsExplanation || !record.note.isBlank
    }
}

private let fullInitialRentFormCantons2026: Set<SwissCanton> = [.be, .bs, .fr, .ge, .lu, .zg, .zh]
private let conditionalInitialRentFormCantons2026: Set<SwissCanton> = [.ne, .vd]

extension HandoverProtocol {
    /// Resolves the small canton layer from the object's canton and the relevant legal dates.
    ///
    /// The initial-rent-form table is deliberately limited to its official 2026 snapshot. An
    /// initial-rent-form rule follows the lease conclusion date, not the later key handover. A
    /// missing or different-year date asks the operator to verify the then-current rule instead
    /// of silently using stale vacancy data. Vaud RULV periods still follow the handover date.
    public func resolvedLegalOverlay() -> ResolvedLegalOverlay? {
        guard let canton = objectCanton, let date = LocalDate.parse(handoverDate) else { return nil }
        let initialRentReferenceDate = LocalDate.parse(contract.conclusionDate)
        let profile = legalProfile()
        let initialRentFormRule: InitialRentFormRule
        if initialRentReferenceDate?.year != 2026 {
            initialRentFormRule = .verifyCurrent
        } else if fullInitialRentFormCantons2026.contains(canton) {
            initialRentFormRule = .required
        } else if conditionalInitialRentFormCantons2026.contains(canton) {
            initialRentFormRule = .conditionalLocal
        } else {
            initialRentFormRule = .notRequired
        }

        var requirements: [LegalRequirement] = []
        // Local termination dates, contractual appointment terms and public holidays can affect
        // practical timing even though the core handover record is governed federally.
        requirements.append(.leaseAndLocalTiming)
        if kind == .entry, initialRentFormRule != .notRequired {
            requirements.append(.initialRentForm)
        }
        if profile.isVaudRulv {
            if kind == .entry {
                if deposit.kind != .none { requirements.append(.depositProof) }
                requirements.append(.tenantLiabilityInsurance)
                requirements.append(.landlordLiabilityInsurance)
            } else {
                requirements.append(.vaudExitReadiness)
            }
        }

        return ResolvedLegalOverlay(
            canton: canton,
            handoverDate: date,
            initialRentReferenceDate: initialRentReferenceDate,
            profile: profile,
            initialRentFormRule: initialRentFormRule,
            requirements: requirements
        )
    }
}
