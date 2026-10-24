import Foundation
import Testing
@testable import LimenKit

@Suite struct ParityRulesTests {
    private func draft(_ canton: SwissCanton = .ag) -> HandoverProtocol {
        var record = HandoverProtocol(id: "synthetic-parity", kind: .entry, createdEpochMs: 1)
        record.address = "Teststrasse 1"
        record.place = "5000 Aarau"
        record.objectCanton = canton
        record.handoverDate = "2026-10-14"
        record.handoverTime = "13:00"
        record.contract.conclusionDate = "2026-10-01"
        record.parties = [Party(.tenant, name: "A"), Party(.landlord, name: "B")]
        record.parties[0].id = "tenant-a"
        record.parties[1].id = "landlord-b"
        record.rooms = [Room(id: "room", kind: .room, inspected: true)]
        record.dossier = [.keys]
        record.dossierChosen = true
        record.keyTransfer = .noPhysicalKeys
        if let overlay = record.resolvedLegalOverlay() {
            for requirement in overlay.requirements { record.legalOverlay = record.legalOverlay.withStatus(requirement, .confirmed) }
        }
        record.signatures = record.parties.map { party in
            var signature = Signature(party.role, name: party.name, plane: .record, refused: true)
            signature.participantId = party.id
            return signature
        }
        return record
    }

    private func issues(_ record: HandoverProtocol) throws -> [FinalizationIssue] {
        let root = try temporaryRoot()
        return CompletionRules.protocolCompletionIssues(record, requiredRoles: CompletionRules.requiredRecordRoles(record, fallbackRole: nil),
            photoDir: try makeDir(root.appendingPathComponent("photos")), signatureDir: try makeDir(root.appendingPathComponent("ink")))
    }

    @Test func everyCantonHasDatedInitialFormAndCommonAuthorityGuidance() {
        let required: Set<SwissCanton> = [.be, .bs, .fr, .ge, .lu, .zg, .zh]
        let conditional: Set<SwissCanton> = [.ne, .vd]
        for canton in SwissCanton.allCases {
            let record = draft(canton)
            #expect(record.resolvedLegalOverlay()?.initialRentFormRule == (required.contains(canton) ? .required : conditional.contains(canton) ? .conditionalLocal : .notRequired))
            #expect(record.resolvedLegalOverlay()?.requirements.contains(.leaseAndLocalTiming) == true)
            #expect(record.freezeLegalRules()?.sources.contains(conciliationDirectory) == true)
            var undated = record
            undated.contract.conclusionDate = ""
            #expect(undated.resolvedLegalOverlay()?.initialRentFormRule == .verifyCurrent)
            undated.contract.conclusionDate = "2025-12-31"
            #expect(undated.resolvedLegalOverlay()?.initialRentFormRule == .verifyCurrent)
        }
    }

    @Test func neLocalityCategoriesExcludeHalfRoomsAndNeverGuessUnknownLocality() {
        #expect(neInitialRentRule(municipality: "Laténa", rooms: "3.5") == .notRequired)
        #expect(neInitialRentRule(municipality: "Latena", rooms: "4,5") == .required)
        #expect(neInitialRentRule(municipality: "La Grande Béroche", rooms: "2") == .notRequired)
        #expect(neInitialRentRule(municipality: "La Grande Béroche", rooms: "3") == .required)
        #expect(neInitialRentRule(municipality: "Neuchâtel", rooms: "5.5") == .required)
        #expect(neInitialRentRule(municipality: "Neuchâtel", rooms: "6") == .notRequired)
        #expect(neInitialRentRule(municipality: "Neuchatel typo", rooms: "3") == .conditionalLocal)
        for input in ["", "NaN", "inf", "-3", "1e100"] {
            #expect(neInitialRentRule(municipality: "Neuchâtel", rooms: input) == .conditionalLocal)
        }
    }

    @Test func vaudDistrictAndDepositTriggersAreIndependent() {
        var vaud = draft(.vd)
        #expect(vaud.resolvedLegalOverlay()?.initialRentFormRule == .conditionalLocal)
        vaud.details.district = "Aigle"
        #expect(vaud.resolvedLegalOverlay()?.initialRentFormRule == .notRequired)
        vaud.details.district = "Lausanne"
        #expect(vaud.resolvedLegalOverlay()?.initialRentFormRule == .required)
        for canton in [SwissCanton.fr, .ge, .ti] {
            var record = draft(canton)
            #expect(record.resolvedLegalOverlay()?.requirements.contains(.cantonalDepositHandling) == false)
            record.deposit.kind = .unknown
            #expect(record.resolvedLegalOverlay()?.requirements.contains(.cantonalDepositHandling) == true)
            record.deposit.kind = .insurance
            #expect(record.resolvedLegalOverlay()?.requirements.contains(.cantonalDepositHandling) == true)
        }
    }

    @Test func eachUnresolvedCheckNeedsItsOwnExplanation() throws {
        let overlay = try #require(draft(.vd).resolvedLegalOverlay())
        var checks = LegalOverlayRecord()
        for requirement in overlay.requirements { checks = checks.withStatus(requirement, .toVerify) }
        checks.note = "Generic shared text cannot explain every missing document"
        #expect(!overlay.isComplete(checks))
        for requirement in overlay.requirements { checks.notes[requirement] = "Awaiting this specific evidence: \(requirement.rawValue)" }
        #expect(overlay.isComplete(checks))
        checks.notes[.initialRentForm] = ""
        checks = checks.withStatus(.initialRentForm, .confirmed)
        #expect(!overlay.isComplete(checks))
    }

    @Test func frozenAndLegacyResolversKeepTheirMeaningWithoutMutation() throws {
        var record = draft(.ne)
        record.details.municipality = "Laténa"
        record.details.habitableRooms = "3"
        record.details.legalSnapshot = record.freezeLegalRules()
        record.finalizedEpochMs = 2
        record.evidenceFingerprint = "test-frozen"
        let stored = ProtocolJSON.encode(record, encodeDefaults: true).compact
        record.details.habitableRooms = "4"
        #expect(record.resolvedLegalOverlay()?.initialRentFormRule == .notRequired)
        var legacy = draft(.ne)
        legacy.legalOverlay.ruleSetId = "ch-tenancy-2026.1"
        legacy.finalizedEpochMs = 2
        legacy.evidenceFingerprint = "test-legacy"
        legacy.details.municipality = "Laténa"
        legacy.details.habitableRooms = "4"
        let before = ProtocolJSON.encode(legacy, encodeDefaults: true).compact
        #expect(legacy.resolvedLegalOverlay()?.initialRentFormRule == .conditionalLocal)
        #expect(legacy.resolvedLegalOverlay()?.ruleSetId == "ch-tenancy-2026.1")
        #expect(ProtocolJSON.encode(legacy, encodeDefaults: true).compact == before)
        #expect(legacy.freezeLegalRules() == nil)
        #expect(record.freezeLegalRules() == record.details.legalSnapshot)
        #expect(!stored.isEmpty)
    }

    @Test func onlyDependentLegalChecksAreInvalidated() {
        let record = draft(.vd)
        var next = record
        next.deposit.kind = .bankAccount
        #expect(record.invalidatedLegalRequirements(next: next) == [.depositProof, .cantonalDepositHandling])
        next = record
        next.details.habitableRooms = "3"
        #expect(record.invalidatedLegalRequirements(next: next) == [.initialRentForm])
        // Since Android 1.2.7 the street is no longer a reason: no requirement resolves from it.
        next = record
        next.address = "Different property"
        #expect(record.invalidatedLegalRequirements(next: next).isEmpty)
        next = record
        next.objectCanton = .ge
        #expect(record.invalidatedLegalRequirements(next: next) == Set(LegalRequirement.allCases))
    }

    @Test func aHalfTypedPreviousProtocolDateCannotPassTheGate() throws {
        // The field keeps unfinished text verbatim and the cover prints it, so it is gated like every other date.
        var record = draft()
        record.lastProtocolDate = "31/02/2026"
        #expect(try issues(record).contains(.dossier))
        record.lastProtocolDate = "12/0"
        #expect(CompletionRules.incompleteDossierTarget(record) == "object")
        record.lastProtocolDate = "2026-09-01"
        #expect(try !issues(record).contains(.dossier))
    }

    @Test func everyParticipantNeedsTheirOwnOutcomeReservationAndDelivery() throws {
        var record = draft()
        var second = Party(.tenant, name: "Co-tenant")
        second.id = "tenant-c"
        record.parties.append(second)
        #expect(try issues(record).contains(.recordOutcomes))
        var absent = Signature(.tenant, name: second.name, plane: .record, reservation: "Absent; informed separately")
        absent.participantId = second.id
        absent.outcome = "absent"
        record.signatures.append(absent)
        #expect(try issues(record).isEmpty)
        record.details.reservations[second.id] = ""
        #expect(record.reservationFor(party: second).isEmpty)
        let reopened = try ProtocolJSON.decode(Data(ProtocolJSON.encode(record, encodeDefaults: true).compact.utf8))
        #expect(reopened.reservationFor(party: second).isEmpty)
        record.deliveryReceipts = record.parties.dropLast().map { party in
            var receipt = DeliveryReceipt(party.role, epochMs: 4)
            receipt.participantId = party.id
            return receipt
        }
        #expect(!record.deliveryComplete())
        var finalReceipt = DeliveryReceipt(.tenant, epochMs: 5)
        finalReceipt.participantId = second.id
        record.deliveryReceipts.append(finalReceipt)
        #expect(record.deliveryComplete())
    }

    @Test func independentTenantPositionsRetainClaimAndCosts() throws {
        var record = draft()
        var finding = Defect(id: "finding", roomId: "room", text: "Marked surface", chargedToTenant: true, fixBy: .landlord, fixDeadline: "2026-10-20", costNote: "Estimate pending")
        finding.participantPositions["tenant-a"] = TenantPosition(response: .normalWear, comment: "Normal age")
        finding.participantPositions["tenant-c"] = TenantPosition(response: .disputes, comment: "Already present")
        record.defects = [finding]
        let reopened = try ProtocolJSON.decode(Data(ProtocolJSON.encode(record, encodeDefaults: true).compact.utf8))
        #expect(reopened.defects == [finding])
        #expect(reopened.defects[0].chargedToTenant)
        #expect(reopened.defects[0].costNote == "Estimate pending")
    }

    @Test func invalidDraftDatesNumbersAndResidualValuesBlockCompletion() throws {
        var record = draft()
        record.handoverDate = "31/02/2026"
        record.handoverTime = "25:01"
        record.contract.startDate = "29/02/2027"
        #expect(try issues(record).contains(.handoverDate))
        #expect(try issues(record).contains(.handoverTime))
        #expect(try issues(record).contains(.dossier))
        for value in ["NaN", "Infinity", "-1", "1e400", "12oops", "1,2,3"] { #expect(NumberValidation.nonNegativeNumber(value) == nil) }
        for value in ["CHF 2’400.-", "2'400,00", "Fr. 2400.–"] { #expect(NumberValidation.nonNegativeNumber(value) == 2400) }
        #expect(Zeitwert.replacementResidualValue(costChf: .nan, lifespanYears: 8, ageYears: 1) == nil)
        #expect(Zeitwert.replacementResidualValue(costChf: 100, lifespanYears: .infinity, ageYears: 1) == nil)
        #expect(Zeitwert.replacementResidualValue(costChf: 100, lifespanYears: 8, ageYears: 9) == 0)
        record = draft()
        record.details.estimates["finding"] = ReplacementEstimate(replacementChf: "100", ageYears: "1", lifeYears: "0")
        #expect(try issues(record).contains(.dossier))
        record = draft()
        record.deposit.kind = .unknown
        record.details.readings = [MeterReading(id: "reading")]
        #expect(try issues(record).contains(.dossier))
        #expect(CompletionRules.incompleteDossierTarget(record) == "readings")
    }

    @Test func honestScopeNoDepositAndUnavailableRoomsAreRecordable() throws {
        var record = draft()
        record.deposit.kind = .none
        record.dossier.append(.deposit)
        #expect(try issues(record).isEmpty)
        record.deposit.kind = .unknown
        #expect(try issues(record).contains(.dossier))
        record.details.scopeNotes["Deposit"] = "The lease is not available"
        record.rooms[0].inspected = false
        record.details.scopeNotes["room"] = "Locked; occupant absent"
        #expect(try issues(record).isEmpty)
        record.dossier.removeAll { $0 == .keys }
        #expect(try issues(record).contains(.keys))
        record.details.scopeNotes["Keys"] = "Separate transfer is arranged"
        #expect(try issues(record).isEmpty)
    }

    @Test func exitSeedPreservesCoTenantsAndContractualLandlord() {
        var record = draft()
        record.parties.append(Party(.tenant, name: "Co-tenant"))
        record.parties[1].agency = "Agency"
        record.parties[1].representedBy = "Previous representative"
        record.parties[1].authority = "Previous mandate"
        var identity = SessionIdentity()
        identity.firstName = "Current representative"
        identity.company = "Agency"
        let parties = record.partiesForExit(role: .landlord, identity: identity)
        #expect(parties.map(\.name) == record.parties.map(\.name))
        #expect(parties[1].representedBy == "Current representative")
        #expect(parties[1].authority.isEmpty)
    }
}
