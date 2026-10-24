import Foundation
import Testing
@testable import LimenKit

@Suite struct SwissDateTests {
    @Test func storedIsIsoAndShownIsSwiss() {
        #expect(SwissDate.display("2026-08-17") == "17/08/2026")
        #expect(SwissDate.toStored("17/08/2026") == "2026-08-17")
    }

    @Test func aDayThatDoesNotExistIsNotADate() {
        #expect(SwissDate.toStored("31/02/2026") == nil)
        #expect(SwissDate.toStored("32/01/2026") == nil)
        #expect(SwissDate.toStored("01/13/2026") == nil)
    }

    @Test func theLeapDayIsADateEveryFourthYear() {
        #expect(SwissDate.toStored("29/02/2028") == "2028-02-29")
        #expect(SwissDate.toStored("29/02/2027") == nil)
    }

    @Test func anIncompleteDateIsNotYetAnAnswer() {
        #expect(SwissDate.toStored("") == nil)
        #expect(SwissDate.toStored("17/0") == nil)
        #expect(SwissDate.toStored("17/08/202") == nil)
    }

    @Test func theMaskPutsTheSeparatorsBackWhereverTypingStarted() {
        #expect(SwissDate.mask("17082026") == "17/08/2026")
        #expect(SwissDate.mask("17/08/2026") == "17/08/2026")
        #expect(SwissDate.mask("170") == "17/0")
        #expect(SwissDate.mask("17.08.2026") == "17/08/2026")
        #expect(SwissDate.mask("2026-08-17") == "20/26/0817")
    }

    @Test func whatWasNeverADatePassesThroughInsteadOfBeingLost() {
        #expect(SwissDate.display("end of the month") == "end of the month")
        #expect(SwissDate.display("") == "")
    }

    @Test func timeIsTwentyFourHourAndChecked() {
        #expect(SwissDate.toStoredTime("0830") == "08:30")
        #expect(SwissDate.toStoredTime("23:59") == "23:59")
        #expect(SwissDate.toStoredTime("24:00") == nil)
        #expect(SwissDate.toStoredTime("12:60") == nil)
        #expect(SwissDate.toStoredTime("8:3") == nil)
        #expect(SwissDate.maskTime("083") == "08:3")
    }
}

@Suite struct ClocksTests {
    @Test func weekendDoesNotCount() {
        let friday = LocalDate(2026, 7, 31)
        #expect(Clocks.addWorkingDays(friday, 2) == LocalDate(2026, 8, 4))
        #expect(Clocks.addWorkingDays(friday, 3) == LocalDate(2026, 8, 5))
    }

    @Test func midweekRunsStraightThrough() {
        #expect(Clocks.addWorkingDays(LocalDate(2026, 8, 3), 2) == LocalDate(2026, 8, 5))
    }

    @Test func holidaysAreSkippedWhenGiven() {
        let thursday = LocalDate(2026, 7, 30)
        #expect(Clocks.addWorkingDays(thursday, 2, holidays: [LocalDate(2026, 7, 31)]) == LocalDate(2026, 8, 4))
    }

    @Test func returnDueShiftsSundayOrRecognizedHolidayButNotSaturday() {
        let saturday = LocalDate(2026, 8, 1)
        #expect(Clocks.returnDue(saturday) == saturday)
        #expect(Clocks.returnDue(LocalDate(2026, 8, 2)) == LocalDate(2026, 8, 3))
        let wednesday = LocalDate(2026, 8, 5)
        #expect(Clocks.returnDue(wednesday, holidays: [wednesday]) == LocalDate(2026, 8, 6))
    }

    @Test func planningDateRequiresActualTransferAndRecordedClause() {
        var record = HandoverProtocol(id: "planning", kind: .entry, createdEpochMs: 1)
        record.handoverDate = "2026-07-31"
        #expect(Clocks.agreedPlanningDate(record) == nil)
        record.details.actualTransferDate = "2026-08-02"
        record.details.notificationDays = "10"
        #expect(Clocks.agreedPlanningDate(record) == nil)
        record.details.notificationClause = "Lease section 8, agreed period"
        #expect(Clocks.agreedPlanningDate(record) == LocalDate(2026, 8, 12))
    }

    @Test func depositBackstopIsOneYear() {
        #expect(Clocks.depositFreeAfter(LocalDate(2026, 9, 30)) == LocalDate(2027, 9, 30))
    }

    @Test func workingDayPredicate() {
        #expect(Clocks.isWorkingDay(LocalDate(2026, 8, 3)))
        #expect(!Clocks.isWorkingDay(LocalDate(2026, 8, 2)))
        #expect(!Clocks.isWorkingDay(LocalDate(2026, 8, 3), holidays: [LocalDate(2026, 8, 3)]))
    }

    @Test func theEpochDayRoundTripsAndTheWeekdayIsJavas() {
        let day = LocalDate(2026, 9, 4)
        #expect(LocalDate.ofEpochDay(day.epochDay) == day)
        #expect(day.dayOfWeek == 5)
        #expect(LocalDate.parse("2026-02-29") == nil)
        #expect(LocalDate(2024, 2, 29).plusYears(1) == LocalDate(2025, 2, 28))
    }
}

@Suite struct ZeitwertTests {
    @Test func halfLifeIsHalfShare() {
        #expect(abs(Zeitwert.remainingFraction(lifespanYears: 8, ageYears: 4) - 0.5) < 1e-9)
        #expect(abs(Zeitwert.tenantShare(costChf: 1200, lifespanYears: 8, ageYears: 4) - 600) < 1e-9)
    }

    @Test func pastLifespanIsZeroHoweverRealTheDamage() {
        #expect(Zeitwert.tenantShare(costChf: 5000, lifespanYears: 8, ageYears: 8) == 0)
        #expect(Zeitwert.tenantShare(costChf: 5000, lifespanYears: 8, ageYears: 23) == 0)
    }

    @Test func brandNewIsFullShare() {
        #expect(abs(Zeitwert.tenantShare(costChf: 1200, lifespanYears: 8, ageYears: 0) - 1200) < 1e-9)
    }

    @Test func negativeAgeIsInvalidRatherThanANewReplacement() {
        #expect(Zeitwert.replacementResidualValue(costChf: 500, lifespanYears: 8, ageYears: -2) == nil)
    }

    @Test func zeroLifespanNeverDivides() {
        #expect(Zeitwert.remainingFraction(lifespanYears: 0, ageYears: 3) == 0)
    }

    @Test func zeroOrNegativeCostIsZero() {
        #expect(Zeitwert.tenantShare(costChf: 0, lifespanYears: 8, ageYears: 1) == 0)
        #expect(Zeitwert.tenantShare(costChf: -50, lifespanYears: 8, ageYears: 1) == 0)
    }

    @Test func theAslocaWallpaperExample() {
        #expect(abs(Zeitwert.remainingFraction(lifespanYears: 10, ageYears: 8) - 0.2) < 1e-9)
    }

    @Test func shippedTableHoldsTheCanonicalValues() {
        #expect(Lifespans.yearsOf(.dispersionPaint) == 8)
        #expect(Lifespans.yearsOf(.fridge) == 10)
        #expect(Lifespans.yearsOf(.solidParquet) == 40)
        #expect(Lifespans.yearsOf(.blindStraps) == 8)
    }
}

@Suite struct TemplatesTests {
    @Test func everyRoomKindStartsWithRows() {
        for kind in RoomKind.allCases { #expect(!Templates.itemsFor(kind).isEmpty, "\(kind) has no template rows") }
    }

    @Test func noTemplateRepeatsARow() {
        for kind in RoomKind.allCases {
            let items = Templates.itemsFor(kind)
            #expect(items.count == Set(items).count, "\(kind) repeats a row")
        }
    }

    @Test func theKitchenKnowsItsAppliances() {
        let kitchen = Templates.itemsFor(.kitchen)
        for item in [ItemKey.stove, .oven, .ovenAccessories, .extractorHood, .fridge, .sink, .tap] {
            #expect(kitchen.contains(item), "kitchen misses \(item)")
        }
    }

    @Test func theBathroomKnowsItsFittings() {
        let bath = Templates.itemsFor(.bathroom)
        for item in [ItemKey.bathtub, .showerHose, .wc, .wcSeat, .washbasin] { #expect(bath.contains(item)) }
    }

    @Test func theWalkStartsAtTheDoorAndEndsAtTheMailbox() {
        let rooms = Templates.defaultRooms
        #expect(rooms.first == .hall)
        #expect(rooms.last == .mailbox)
        #expect(rooms.contains(.kitchen))
        #expect(rooms.contains(.bathroom))
    }
}

@Suite struct CautionProviderTests {
    @Test func recognizesListedInsurersByTheCertificateName() {
        #expect(CautionProvider.fromStoredName("SwissCaution") == .swissCaution)
        #expect(CautionProvider.fromStoredName(" goCaution ") == .goCaution)
        #expect(CautionProvider.fromStoredName("Zurich") == .zurich)
    }

    @Test func preservesAnUnlistedInsurerAsOther() {
        #expect(CautionProvider.fromStoredName("Local Guarantee SA") == .other)
    }
}

@Suite struct LegalProfileTests {
    private func record(_ canton: SwissCanton?, _ date: String, incorporated: Bool = false) -> HandoverProtocol {
        var p = HandoverProtocol(id: "p1", kind: .entry, createdEpochMs: 1)
        p.objectCanton = canton
        p.handoverDate = date
        p.romandFrameworkInLease = incorporated
        return p
    }

    @Test func vaudRulvSelectsThePreviousAndCurrentBindingPeriods() {
        #expect(record(.vd, "2020-06-30").legalProfile() == .federalAndLease)
        #expect(record(.vd, "2020-07-01").legalProfile() == .vaudRulv2020)
        #expect(record(.vd, "2026-06-30").legalProfile() == .vaudRulv2020)
        #expect(record(.vd, "2026-07-01").legalProfile() == .vaudRulv2026)
        #expect(record(.vd, "2032-06-30").legalProfile() == .vaudRulv2026)
        #expect(record(.vd, "2032-07-01").legalProfile() == .federalAndLease)
    }

    @Test func romandFrameworkIsContractualOutsideThatRule() {
        #expect(SwissCanton.ju.supportsRomandFramework)
        #expect(!SwissCanton.zh.supportsRomandFramework)
        #expect(record(.ju, "2026-08-18", incorporated: true).legalProfile() == .romandContractual)
        #expect(record(.ju, "2026-08-18").legalProfile() == .federalAndLease)
    }
}

@Suite struct LegalOverlayTests {
    private func record(_ canton: SwissCanton, date: String = "2026-08-18", kind: Kind = .entry, depositKind: DepositKind = .none) -> HandoverProtocol {
        var p = HandoverProtocol(id: "p-\(canton.code)-\(date)-\(kind)", kind: kind, createdEpochMs: 1)
        p.objectCanton = canton
        p.handoverDate = date
        p.contract.conclusionDate = date
        p.deposit.kind = depositKind
        return p
    }

    @Test func initialRentFormUsesOnlyTheDated2026OfficialSnapshot() {
        for canton in [SwissCanton.be, .bs, .fr, .ge, .lu, .zg, .zh] {
            #expect(record(canton).resolvedLegalOverlay()?.initialRentFormRule == .required)
        }
        for canton in [SwissCanton.ne, .vd] {
            #expect(record(canton).resolvedLegalOverlay()?.initialRentFormRule == .conditionalLocal)
        }
        #expect(record(.ag).resolvedLegalOverlay()?.initialRentFormRule == .notRequired)
        #expect(record(.zh, date: "2027-01-01").resolvedLegalOverlay()?.initialRentFormRule == .verifyCurrent)
    }

    @Test func initialRentFormUsesLeaseConclusionDateNotTheLaterHandover() {
        var handoverIn2027 = record(.zh, date: "2027-01-08")
        handoverIn2027.contract = Contract()
        handoverIn2027.contract.conclusionDate = "2026-12-14"
        #expect(handoverIn2027.resolvedLegalOverlay()?.initialRentFormRule == .required)
        var unknown = handoverIn2027
        unknown.contract = Contract()
        #expect(unknown.resolvedLegalOverlay()?.initialRentFormRule == .verifyCurrent)
    }

    @Test func vaudEntryAndExitReceiveDifferentChecksWithoutForkingTheFlow() throws {
        let entry = try #require(record(.vd).resolvedLegalOverlay())
        #expect(entry.requirements == [.leaseAndLocalTiming, .initialRentForm, .tenantLiabilityInsurance, .landlordLiabilityInsurance])
        let withDeposit = try #require(record(.vd, depositKind: .bankAccount).resolvedLegalOverlay())
        #expect(withDeposit.requirements.contains(.depositProof))
        let exit = try #require(record(.vd, kind: .exit).resolvedLegalOverlay())
        #expect(exit.requirements == [.leaseAndLocalTiming, .vaudExitReadiness])
    }

    @Test func typingInTheAddressOrPlaceInvalidatesNoLegalCheck() {
        let before = record(.vd)
        var next = before
        next.address = "Rue de Bourg 1"
        #expect(before.invalidatedLegalRequirements(next: next).isEmpty)
        next = before
        next.place = "1003 Lausanne"
        #expect(before.invalidatedLegalRequirements(next: next).isEmpty)
    }

    @Test func movingTheCantonInvalidatesEveryLegalCheck() {
        let before = record(.vd)
        var next = before
        next.objectCanton = .ge
        #expect(before.invalidatedLegalRequirements(next: next) == Set(LegalRequirement.allCases))
    }

    @Test func missingAndExceptionalOutcomesStayRecordableButNeedAnExplanation() throws {
        let overlay = try #require(record(.ag, kind: .exit).resolvedLegalOverlay())
        #expect(!overlay.isComplete(LegalOverlayRecord()))
        let disputed = LegalOverlayRecord().withStatus(.leaseAndLocalTiming, .missingOrDisputed)
        #expect(!overlay.isComplete(disputed))
        var explained = disputed
        explained.notes[.leaseAndLocalTiming] = "Lease gives a different appointment."
        #expect(overlay.isComplete(explained))
        #expect(overlay.isComplete(LegalOverlayRecord().withStatus(.leaseAndLocalTiming, .confirmed)))
    }
}

@Suite struct ReportTests {
    private var record: HandoverProtocol {
        var p = HandoverProtocol(id: "p1", kind: .exit, createdEpochMs: 1)
        p.rooms = [Room(id: "kitchen", kind: .kitchen), Room(id: "bath", kind: .bathroom), Room(id: "hall", kind: .hall)]
        p.objects = [ObjectEntry(id: "o1", group: .appliance, catalogue: Appliance.fridge.rawValue)]
        p.defects = [
            Defect(id: "d1", roomId: "kitchen", item: .worktop, text: "Burn mark"),
            Defect(id: "d2", text: "Door seal split", objectId: "o1"),
            Defect(id: "d3", roomId: "bath", item: .custom, text: "Bent", itemLabel: "Shower rail"),
            Defect(id: "d4", roomId: "kitchen", text: "Ceiling stain"),
        ]
        return p
    }

    @Test func aRoomContributesItsFindingsAndNothingElse() {
        #expect(Report.roomFindings(record, "kitchen").map(\.defect.id) == ["d1", "d4"])
        #expect(Report.roomFindings(record, "bath").map(\.defect.id) == ["d3"])
    }

    @Test func aRoomWithNothingWrongInItContributesNothing() {
        #expect(Report.roomFindings(record, "hall").isEmpty)
    }

    @Test func numberingIsThePositionInTheWholeRecordNotWithinTheRoom() {
        #expect(Report.roomFindings(record, "kitchen").map(\.number) == [1, 4])
        #expect(Report.roomFindings(record, "bath").map(\.number) == [3])
        #expect(Report.objectFindings(record).map(\.number) == [2])
    }

    @Test func aFindingAboutAnObjectIsNotAFindingAboutARoom() {
        #expect(!Report.roomFindings(record, "kitchen").contains { $0.defect.id == "d2" })
        #expect(Report.objectFindings(record).map(\.defect.id) == ["d2"])
    }

    @Test func everyFindingReachesExactlyOnePlaceOnThePaper() {
        let printed = record.rooms.flatMap { Report.roomFindings(record, $0.id) } + Report.objectFindings(record) + Report.orphanedFindings(record)
        #expect(printed.count == record.defects.count)
        #expect(Set(printed.map(\.defect.id)) == Set(record.defects.map(\.id)))
    }

    @Test func aFindingWhoseRoomIsGoneStillReachesThePaper() {
        var lost = record
        lost.rooms.removeAll { $0.id == "bath" }
        #expect(Report.orphanedFindings(lost).map(\.defect.id) == ["d3"])
        #expect(Report.orphanedFindings(lost).map(\.number) == [3])
        let printed = lost.rooms.flatMap { Report.roomFindings(lost, $0.id) } + Report.objectFindings(lost) + Report.orphanedFindings(lost)
        #expect(printed.count == lost.defects.count)
    }

    @Test func theAnnexCitesFindingsByNumberAndObjectsByName() {
        var withPhotos = record
        withPhotos.defects[2].photos = ["d3-1.jpg"]
        withPhotos.defects[2].photoEvidence = [PhotoEvidence("d3-1.jpg", sha256: "ABC")]
        withPhotos.objects[0].photos = ["o1-1.jpg", "o1-2.jpg"]
        let plates = Report.plates(withPhotos)
        #expect(plates.map(\.file) == ["d3-1.jpg", "o1-1.jpg", "o1-2.jpg"])
        #expect(plates[0].owner == .finding(3))
        #expect(plates[0].sha256 == "ABC")
        if case .supplied(let entry) = plates[1].owner { #expect(entry.id == "o1") } else { Issue.record("not a supplied plate") }
    }

    @Test func aRecordWithoutPhotographsHasNoAnnex() {
        #expect(Report.plates(record).isEmpty)
    }

    @Test func evidenceMetadataAloneStillReachesTheAnnex() {
        var migrated = record
        migrated.defects[0].photoEvidence = [PhotoEvidence("legacy.jpg", sha256: "ABC")]
        #expect(Report.plates(migrated).map(\.file) == ["legacy.jpg"])
    }
}

@Suite struct ProtocolIntegrityTests {
    @Test func fingerprintCoversTheFrozenRecordAndOriginalEvidence() throws {
        let root = try temporaryRoot()
        let photos = try makeDir(root.appendingPathComponent("photos"))
        let ink = try makeDir(root.appendingPathComponent("ink"))
        try writeText("original photo bytes", to: photos.appendingPathComponent("wall.jpg"))
        try writeText("original ink bytes", to: ink.appendingPathComponent("tenant-record.png"))

        var draft = HandoverProtocol(id: "p1", kind: .exit, createdEpochMs: 1)
        draft.address = "Rue Test 1"
        draft.defects = [Defect(id: "d1", roomId: "r1", text: "Stain", photos: ["wall.jpg"], photoEvidence: [PhotoEvidence("wall.jpg", sha256: try ProtocolIntegrity.fileHash(photos.appendingPathComponent("wall.jpg")))])]
        draft.signatures = [Signature(.tenant, plane: .record, file: "tenant-record.png")]
        draft.finalizedEpochMs = 12
        var frozen = draft
        frozen.evidenceFingerprint = try ProtocolIntegrity.fingerprint(draft, photoDir: photos, signatureDir: ink)

        #expect(frozen.evidenceFingerprint.count == 64)
        #expect(ProtocolIntegrity.matches(frozen, photoDir: photos, signatureDir: ink))
        var exported = frozen
        exported.exportedEpochMs = 13
        #expect(ProtocolIntegrity.matches(exported, photoDir: photos, signatureDir: ink))
        var delivered = frozen
        delivered.deliveryReceipts = [DeliveryReceipt(.tenant, epochMs: 14)]
        delivered.deliveryMetadataEpochMs = 14
        #expect(ProtocolIntegrity.matches(delivered, photoDir: photos, signatureDir: ink))

        try writeText("changed photo bytes", to: photos.appendingPathComponent("wall.jpg"))
        #expect(!ProtocolIntegrity.matches(frozen, photoDir: photos, signatureDir: ink))
    }

    @Test func inkOnlyAppliesToTheRevisionItSaw() {
        var signed = HandoverProtocol(id: "p1", kind: .entry, createdEpochMs: 1)
        signed.signatures = [Signature(.tenant, plane: .record, file: "tenant-record.png", contentRevision: 3)]
        signed.contentRevision = 3
        #expect(signed.isSigned())
        signed.contentRevision = 4
        #expect(!signed.isSigned())
    }

    @Test func missingEvidenceFailsClosed() throws {
        let root = try temporaryRoot()
        let photos = try makeDir(root.appendingPathComponent("missing-photos"))
        let ink = try makeDir(root.appendingPathComponent("missing-ink"))
        var record = HandoverProtocol(id: "p2", kind: .entry, createdEpochMs: 1)
        record.defects = [Defect(id: "d2", photos: ["gone.jpg"])]
        #expect(ProtocolIntegrity.missingEvidence(record, photoDir: photos, signatureDir: ink) == ["photo/gone.jpg"])
        #expect(throws: ProtocolIntegrity.IntegrityError.self) { try ProtocolIntegrity.fingerprint(record, photoDir: photos, signatureDir: ink) }
        record.finalizedEpochMs = 2
        record.evidenceFingerprint = "not-a-real-fingerprint"
        #expect(!ProtocolIntegrity.matches(record, photoDir: photos, signatureDir: ink))
    }
}

@Suite struct CompletionRulesTests {
    private func complete(_ kind: Kind, _ role: Role, company: String = "") -> HandoverProtocol {
        var p = HandoverProtocol(id: "p-\(kind)-\(role)-\(company)", kind: kind, createdEpochMs: 1)
        p.sessionRole = role
        p.sessionName = "Starter"
        p.address = "Rue Test 1"
        p.place = "1000 Lausanne"
        p.objectCanton = .vd
        p.handoverDate = "2026-08-18"
        p.handoverTime = "10:00"
        p.contract.conclusionDate = "2026-08-01"
        p.details.district = "Lausanne"
        var overlay = LegalOverlayRecord()
        if kind == .entry {
            overlay = overlay.withStatus(.leaseAndLocalTiming, .confirmed).withStatus(.initialRentForm, .confirmed)
                .withStatus(.tenantLiabilityInsurance, .confirmed).withStatus(.landlordLiabilityInsurance, .confirmed)
        } else {
            overlay = overlay.withStatus(.leaseAndLocalTiming, .confirmed).withStatus(.vaudExitReadiness, .confirmed)
        }
        p.legalOverlay = overlay
        p.parties = [Party(.tenant, name: "Tenant"), Party(.landlord, name: company.ifBlank("Landlord"))]
        p.rooms = [Room(id: "r1", kind: .room, inspected: true)]
        p.keys = [KeyCount(.apartment, count: 2)]
        p.dossier = [.keys]
        p.keyTransfer = .allTransferred
        p.signatures = [Signature(.tenant, plane: .record, refused: true), Signature(.landlord, plane: .record, refused: true)]
        return p
    }

    private func issues(_ record: HandoverProtocol) throws -> [FinalizationIssue] {
        let root = try temporaryRoot()
        return CompletionRules.protocolCompletionIssues(
            record,
            requiredRoles: CompletionRules.requiredRecordRoles(record, fallbackRole: record.sessionRole),
            photoDir: try makeDir(root.appendingPathComponent("photos")),
            signatureDir: try makeDir(root.appendingPathComponent("ink"))
        )
    }

    @Test func bothHandoffsWorkForTenantPrivateLandlordAndAgency() throws {
        for kind in Kind.allCases {
            #expect(try issues(complete(kind, .tenant)).isEmpty, "tenant \(kind)")
            #expect(try issues(complete(kind, .landlord)).isEmpty, "private landlord \(kind)")
            #expect(try issues(complete(kind, .landlord, company: "Example Agency SA")).isEmpty, "agency \(kind)")
        }
    }

    @Test func unilateralRecordRequiresItsReasonAndOnlyThePresentSideOutcome() throws {
        var base = complete(.exit, .tenant)
        base.oneSided = true
        base.signatures = [Signature(.tenant, plane: .record, refused: true)]
        #expect(CompletionRules.requiredRecordRoles(base, fallbackRole: nil) == [.tenant])
        #expect(try issues(base).contains(.unilateralReason))
        var reasoned = base
        reasoned.unilateralReason = .otherPartyAbsent
        #expect(try issues(reasoned).isEmpty)
        var sideless = reasoned
        sideless.sessionRole = nil
        sideless.signatures = []
        #expect(try issues(sideless).contains(.recordOutcomes))
    }

    @Test func uncheckedScopeAndInconsistentKeysBlockFinalization() throws {
        var incomplete = complete(.entry, .tenant)
        incomplete.rooms[0].inspected = false
        incomplete.objects = [ObjectEntry(id: "o1", group: .appliance)]
        incomplete.keys[0].count = 0
        let found = try issues(incomplete)
        #expect(found.contains(.rooms))
        #expect(found.contains(.objects))
        #expect(found.contains(.keys))
    }

    @Test func aSelectedDepositNeedsItsIdentifyingDetails() throws {
        var incomplete = complete(.entry, .tenant)
        incomplete.dossier.append(.deposit)
        incomplete.deposit.kind = .bankAccount
        incomplete.deposit.amountChf = "3000"
        #expect(try issues(incomplete).contains(.dossier))
        var full = incomplete
        full.deposit.bank = "Bank"
        full.deposit.account = "Account"
        full.legalOverlay = full.legalOverlay.withStatus(.depositProof, .confirmed)
        #expect(try issues(full).isEmpty)
    }

    @Test func applicableOverlayChecksBlockFinalizationUntilTheyAreRecorded() throws {
        var blank = complete(.exit, .tenant)
        blank.legalOverlay = LegalOverlayRecord()
        #expect(try issues(blank).contains(.legalOverlay))
        #expect(try issues(complete(.exit, .tenant)).isEmpty)
    }

    @Test func removingTheKeysCardNeedsAnExplanation() throws {
        var withoutKeys = complete(.entry, .tenant)
        withoutKeys.dossier = []
        withoutKeys.dossierChosen = true
        withoutKeys.keys = []
        withoutKeys.keyTransfer = .notRecorded
        #expect(try issues(withoutKeys).contains(.keys))
        withoutKeys.details.scopeNotes["Keys"] = "Keys remain with the caretaker pending a separate transfer"
        #expect(try issues(withoutKeys).isEmpty)
    }

    @Test func theKeysCardStillDemandsAnOutcomeWhileItIsOnTheRecord() throws {
        var unanswered = complete(.entry, .tenant)
        unanswered.keyTransfer = .notRecorded
        #expect(try issues(unanswered) == [.keys])
    }

    @Test func theKeysChipAgreesWithTheGate() throws {
        var noCount = complete(.entry, .tenant)
        noCount.keys = []
        #expect(!CompletionRules.keyOutcomeRecorded(noCount))
        #expect(try issues(noCount) == [.keys])
    }

    @Test func anEmptyInspectionAsksForARoomRatherThanForConfirmation() throws {
        var noRooms = complete(.entry, .tenant)
        noRooms.rooms = []
        let found = try issues(noRooms)
        #expect(found.contains(.noRooms))
        #expect(!found.contains(.rooms))
    }

    @Test func aOneSidedRecordWithNoKnownSideFallsBackToBothSignatures() throws {
        var sideless = complete(.exit, .tenant)
        sideless.oneSided = true
        sideless.unilateralReason = .otherPartyAbsent
        sideless.sessionRole = nil
        #expect(CompletionRules.requiredRecordRoles(sideless, fallbackRole: nil) == [.tenant, .landlord])
        #expect(try issues(sideless).isEmpty)
    }

    /// Every section the dossier chips cover, answered and accepted by the gate.
    private func everySectionAnswered() -> HandoverProtocol {
        var p = complete(.entry, .tenant)
        p.dossier = DossierCard.allCases
        p.dossierChosen = true
        p.contract.monthlyRentChf = "1850"
        p.contract.conclusionDate = "2026-08-01"
        p.deposit.kind = .bankAccount
        p.deposit.amountChf = "3700"
        p.deposit.bank = "BCV"
        p.deposit.account = "CH93 0076 2011 6238 5295 7"
        p.remarks = "Keys handed over at the door"
        p.legalOverlay = p.legalOverlay.withStatus(.depositProof, .confirmed)
        p.details.actualTransferDate = "2026-08-18"
        p.details.actualTransferTime = "10:30"
        // Meters here are readings only, and the legacy six dials stay empty: the card's only way in.
        p.details.readings = [MeterReading(id: "m1", label: "Electricity", identifier: "E-1", value: "4821", unit: "kWh", date: "2026-08-18", time: "10:05")]
        p.details.attachments = [SupportingDocument(id: "a1", title: "Lease", externalReference: "Folder 3")]
        p.details.followUps = [FollowUp(id: "f1", description: "Stain returns after cleaning")]
        return p
    }

    private func chips(_ p: HandoverProtocol) -> [String: Bool] {
        var ticks = [
            "object": CompletionRules.objectRecorded(p),
            "parties": CompletionRules.partiesRecorded(p),
            "transfer": CompletionRules.transferRecorded(p),
            "attachments": CompletionRules.attachmentsRecorded(p),
            "followUps": CompletionRules.followUpsRecorded(p),
        ]
        for card in DossierCard.allCases { ticks[card.rawValue] = CompletionRules.dossierCardRecorded(p, card) }
        return ticks
    }

    @Test func everySectionChipTicksOnARecordTheGateAccepts() throws {
        let full = everySectionAnswered()
        #expect(try issues(full).isEmpty)
        #expect(chips(full).values.allSatisfy { $0 }, "\(chips(full))")
    }

    @Test func aChipDoesNotTickWhereTheGateRejectsItsSection() throws {
        let full = everySectionAnswered()
        var broken: [(String, HandoverProtocol)] = []
        var p = full
        var witness = Party(.witness)
        witness.id = "w1"
        p.parties.append(witness)
        broken.append(("parties", p))
        p = full
        p.parties = [Party(.tenant, name: "Tenant", representedBy: "Agent"), full.parties[1]]
        broken.append(("parties", p))
        p = full
        p.handoverTime = "14:3"
        broken.append(("object", p))
        p = full
        p.lastProtocolDate = "31/02/2026"
        broken.append(("object", p))
        p = full
        p.contract.monthlyRentChf = "abc"
        broken.append(("Contract", p))
        p = full
        p.deposit.amountChf = "3k"
        broken.append(("Deposit", p))
        p = full
        p.details.readings[0].time = "25:99"
        broken.append(("Meters", p))
        p = full
        p.chargesStatementBy = "31/02/2026"
        broken.append(("Notes", p))
        p = full
        p.details.actualTransferTime = "25:99"
        broken.append(("transfer", p))
        p = full
        p.details.attachments = [SupportingDocument(id: "a2")]
        broken.append(("attachments", p))
        p = full
        p.details.followUps = [FollowUp(id: "f2")]
        broken.append(("followUps", p))
        for (section, record) in broken {
            #expect(chips(record)[section] == false, "\(section)")
            #expect(try !issues(record).isEmpty, "\(section)")
        }
    }

    @Test func aContractAnsweredOnlyByItsReasonTicksAndPasses() throws {
        let full = everySectionAnswered()
        var reasonOnly = full
        reasonOnly.contract = Contract()
        reasonOnly.details.scopeNotes["Contract"] = "Lease not available at the handover"
        // Without a conclusion date the initial-rent rule cannot be resolved, and this port's
        // overlay then asks the confirmed check for a note, which is the audit's rule, not 1.2.7's.
        reasonOnly.legalOverlay.notes[.initialRentForm] = "Form seen at the agency"
        #expect(CompletionRules.dossierCardRecorded(reasonOnly, .contract))
        #expect(try issues(reasonOnly).isEmpty)
        var empty = full
        empty.contract = Contract()
        #expect(!CompletionRules.dossierCardRecorded(empty, .contract))
    }

    @Test func aDepositAmountLeftBehindByTheKindPillDoesNotBlockFinalization() throws {
        // The amount field exists only for a bank account and an insurance, so text kept after the
        // pill moved to None is a value nobody can reach to correct.
        var none = everySectionAnswered()
        none.deposit = Deposit()
        none.deposit.kind = .none
        none.deposit.amountChf = "two months"
        #expect(try issues(none).isEmpty)
        #expect(CompletionRules.depositAmountShown(none) == "")
        var bank = none
        bank.deposit.kind = .bankAccount
        bank.deposit.bank = "BCV"
        bank.deposit.account = "CH93 0076 2011 6238 5295 7"
        #expect(try issues(bank).contains(.dossier))
        #expect(CompletionRules.incompleteDossierTarget(bank) == "card-Deposit")
    }

    @Test func theDossierMessageNamesOnlyWhatTheGateRejected() {
        let s = Str(.en)
        let full = everySectionAnswered()
        #expect(CompletionRules.dossierCauses(full, s).isEmpty)
        var p = full
        p.contract.monthlyRentChf = "1.200,50"
        #expect(CompletionRules.dossierCauses(p, s) == [s.monthlyRent])
        p = full
        p.deposit.amountChf = "3k"
        #expect(CompletionRules.dossierCauses(p, s) == [s.depositAmount])
        p = full
        p.lastProtocolDate = "12/0"
        #expect(CompletionRules.dossierCauses(p, s) == [s.lastProtocol])
        p = full
        p.contract = Contract()
        #expect(CompletionRules.dossierCauses(p, s) == [s.contract])
        p = full
        p.details.readings = [MeterReading(id: "m2")]
        #expect(CompletionRules.dossierCauses(p, s) == [s.meters])
        // A wear estimate with its cost left blank is the case the editor itself does not flag.
        var worn = full
        worn.defects = [Defect(id: "d1", roomId: "r1", text: "Scratched floor", chargedToTenant: true)]
        worn.details.estimates["d1"] = ReplacementEstimate(ageYears: "3", lifeYears: "8")
        #expect(CompletionRules.dossierCauses(worn, s) == ["\(s.faceValue): Scratched floor"])
    }

    @Test func aTimeThatIsNotValidIsNamedBesideTheHandoverTimeMessage() throws {
        let s = Str(.en)
        let full = everySectionAnswered()
        #expect(CompletionRules.timeCauses(full, s).isEmpty)
        var bad = full
        bad.details.actualTransferTime = "25:99"
        bad.details.readings[0].time = "9"
        #expect(try issues(bad).contains(.handoverTime))
        #expect(CompletionRules.timeCauses(bad, s) == [s.actualTransfer, "\(s.meters): Electricity"])
    }
}
