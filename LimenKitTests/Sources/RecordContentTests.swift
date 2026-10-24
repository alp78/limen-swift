import Foundation
import Testing
@testable import LimenKit

/// What the supplemental sections of the exported record print, case for case as Android's
/// `RecordContentTest` states it. The paper states what is true of the record as it stands, so a
/// value whose input has gone from the screen must not stay on it, and a label is always the
/// document's own language.
@Suite struct RecordContentTests {
    private let en = Str(.en)

    /// Every component removed but Keys, so no stand-in reason for it is expected on the paper.
    private var draft: HandoverProtocol {
        var p = HandoverProtocol(id: "rc", kind: .exit, createdEpochMs: 1)
        p.dossier = [.keys]
        p.dossierChosen = true
        return p
    }

    private func withNotes(_ p: HandoverProtocol, _ notes: [(String, String)]) -> HandoverProtocol {
        var next = p
        for (key, reason) in notes { next.details.scopeNotes[key] = reason }
        return next
    }

    private func reasons(_ p: HandoverProtocol, _ s: Str? = nil) -> [String] {
        let s = s ?? en
        return RecordContent.extraContent(record: p, strings: s).first { $0.title == s.notInspectedReasons }?.paragraphs ?? []
    }

    private func legal(_ p: HandoverProtocol) -> String {
        (RecordContent.extraContent(record: p, strings: en).first { $0.title == en.legalOverlayTitle }?.paragraphs ?? []).joined(separator: "\n")
    }

    @Test func aRoomReasonPrintsOnlyWhileTheRoomIsNotInspected() {
        var p = draft
        p.rooms = [Room(id: "k", kind: .kitchen), Room(id: "b", kind: .bathroom, inspected: true)]
        p = withNotes(p, [("k", "No access to the kitchen"), ("b", "Tenant refused entry")])
        #expect(reasons(p) == ["\(en.room(.kitchen)): No access to the kitchen"])
    }

    @Test func aSuppliedItemReasonPrintsOnlyWhileTheItemIsNotInspected() {
        var p = draft
        p.objects = [ObjectEntry(id: "o1", group: .other, label: "Garden shed"), ObjectEntry(id: "o2", group: .other, label: "Cellar shelving", inspected: true)]
        p = withNotes(p, [("o1", "Locked"), ("o2", "Key missing")])
        #expect(reasons(p) == ["Garden shed: Locked"])
    }

    @Test func aReasonForAComponentPrintsOnlyWhileThatComponentIsOnTheRecord() {
        let notes = [("Contract", "Lease not at hand"), ("Deposit", "No certificate"), ("Meters", "Dials sealed")]
        var withDeposit = draft
        withDeposit.dossier = [.deposit, .keys]
        #expect(reasons(withNotes(withDeposit, notes)) == ["\(en.dossierCard(.deposit)): No certificate"])
        var withoutDeposit = draft
        withoutDeposit.dossier = [.contract, .meters, .keys]
        #expect(reasons(withNotes(withoutDeposit, notes)) == ["\(en.dossierCard(.contract)): Lease not at hand", "\(en.dossierCard(.meters)): Dials sealed"])
    }

    @Test func theKeysReasonStandsInForARemovedKeysCardAndHidesWhenTheCardIsBack() {
        let note = [("Keys", "Handed over separately")]
        var removed = draft
        removed.dossier = []
        #expect(reasons(withNotes(removed, note)) == ["\(en.dossierCard(.keys)): Handed over separately"])
        #expect(reasons(withNotes(draft, note)).isEmpty)
    }

    @Test func theInspectionReasonPrintsInTheDocumentLanguageAndOnlyForARecordWithoutRooms() {
        let de = Str(.de)
        let noRooms = withNotes(draft, [("Inspection", "No access to the flat")])
        #expect(reasons(noRooms, de) == ["\(de.stepInspection): No access to the flat"])
        #expect(!(reasons(noRooms, de).first ?? "").contains("Inspection"))
        var withRoom = noRooms
        withRoom.rooms = [Room(id: "k", kind: .kitchen, inspected: true)]
        #expect(reasons(withRoom, de).isEmpty)
    }

    @Test func aReasonKeyThatMatchesNothingOnTheRecordIsNotPrintedAsAKey() {
        let p = withNotes(draft, [("cellar", "Locked")])
        #expect(reasons(p).isEmpty)
        #expect(!RecordContent.extraContent(record: p, strings: en).contains { $0.title == en.notInspectedReasons })
    }

    @Test func theWearEstimateNamesItsLifespanRowInTheDocumentLanguage() {
        let fr = Str(.fr)
        func line(_ basis: String) -> String {
            var p = draft
            p.defects = [Defect(id: "d1")]
            p.details.estimates["d1"] = ReplacementEstimate(replacementChf: "400", ageYears: "3", lifeYears: "8", basis: basis)
            return RecordContent.extraContent(record: p, strings: fr).first { $0.title == fr.faceValue }?.paragraphs.first ?? ""
        }
        let picked = line(LifeKey.dispersionPaint.rawValue)
        #expect(picked.hasPrefix("\(fr.defects) 1: \(fr.life(.dispersionPaint))\n"))
        #expect(!picked.contains(LifeKey.dispersionPaint.rawValue))
        #expect(line("").hasPrefix("\(fr.defects) 1: \(fr.customLifespan)\n"))
        #expect(line("Older wording").hasPrefix("\(fr.defects) 1: Older wording\n"))
    }

    @Test func theNeuchatelFactsPrintOnlyForNeuchatelAndTheDistrictOnlyForVaud() {
        func record(_ canton: SwissCanton) -> HandoverProtocol {
            var p = draft
            p.objectCanton = canton
            p.details.municipality = "Neuchâtel"
            p.details.habitableRooms = "4"
            p.details.district = "Lausanne"
            return p
        }
        let ne = legal(record(.ne))
        #expect(ne.contains("Neuchâtel"))
        #expect(!ne.contains("Lausanne"))
        let vd = legal(record(.vd))
        #expect(vd.contains("Lausanne"))
        #expect(!vd.contains("Neuchâtel"))
        let ge = legal(record(.ge))
        #expect(!ge.contains("Neuchâtel"))
        #expect(!ge.contains("Lausanne"))
    }

    @Test func theFollowUpDeadlineUsesThePrintedLabelNotTheInputPrompt() {
        var p = draft
        p.details.followUps = [FollowUp(id: "f1", description: "Mould", deadline: "2026-03-12")]
        let text = RecordContent.extraContent(record: p, strings: en).first { $0.title == en.followUps }?.paragraphs.first ?? ""
        #expect(text.contains("\(en.repairDeadline): 12/03/2026"))
        #expect(!text.contains("(date)"))
    }

    @Test func thePrintedLabelsCarryNoInstructionToThePersonTyping() {
        for lang in Lang.allCases {
            let s = Str(lang)
            #expect(!s.repairDeadline.isBlank && !s.repairDeadline.contains("("), "\(lang) repair deadline")
            #expect(!s.notInspectedReasons.isBlank && !s.notInspectedReasons.contains(":"), "\(lang) reasons heading")
            #expect(!s.meterIdentifier.isBlank && !s.meterIdentifier.contains("("), "\(lang) meter identifier")
        }
        #expect(en.repairDeadline == "Repair deadline")
    }

    @Test func theRomanshDepositReleaseNamesTheLandlordAndWhenTheYearStarts() {
        let rm = Str(.rm).releaseBank
        #expect(rm.contains("Sche il locatur"))
        #expect(rm.contains("suenter la fin da la locaziun"))
        #expect(rm.contains("da la banca"))
    }

    @Test func aForeignCountryIsNamedInTheLanguageOfTheDocument() {
        var berlin = SessionIdentity()
        berlin.postalCode = "10115"
        berlin.city = "Berlin"
        berlin.addressCountry = "DE"
        berlin.usesSwissAddress = false
        #expect(berlin.placeLine(locale: Locale(identifier: "de")) == "10115 Berlin Deutschland")
        #expect(berlin.placeLine(locale: Locale(identifier: "fr")) == "10115 Berlin Allemagne")
        var zurich = SessionIdentity()
        zurich.postalCode = "8001"
        zurich.city = "Zürich"
        #expect(zurich.placeLine(locale: Locale(identifier: "fr")) == "8001 Zürich")
    }

    private func tenant(_ id: String, _ name: String) -> Party {
        var party = Party(.tenant, name: name)
        party.id = id
        return party
    }

    private var positions: OrderedMap<String, TenantPosition> {
        var map = OrderedMap<String, TenantPosition>()
        map["t1"] = TenantPosition(response: .agrees)
        map["t2"] = TenantPosition(response: .disputes, comment: "Not caused by me")
        map["gone"] = TenantPosition(response: .disputes, comment: "Left behind")
        return map
    }

    @Test func eachTenantStillOnTheRecordPrintsItsOwnPositionAndARemovedOneNeverPrintsUnderItsId() {
        var p = draft
        p.parties = [tenant("t1", "Anna"), tenant("t2", "Beat"), Party(.landlord, name: "Lena")]
        var d = Defect(id: "d1")
        d.participantPositions = positions
        let lines = PdfExport.participantPositionLines(p, d, en)
        #expect(lines == ["Anna: \(en.tenantResponse(.agrees))\n", "Beat: \(en.tenantResponse(.disputes))\nNot caused by me"])
        #expect(!lines.contains { $0.contains("gone") || $0.contains("Left behind") })
    }

    @Test func aLoneTenantsPositionsStayOffThePaperBecauseTheEditorHidesThem() {
        var p = draft
        p.parties = [tenant("t1", "Anna"), Party(.landlord, name: "Lena")]
        var d = Defect(id: "d1")
        d.participantPositions = positions
        #expect(PdfExport.participantPositionLines(p, d, en).isEmpty)
    }

    @Test func theOriginalTenantsPositionPrintsUnderTheirNameNotTheLegacyKey() {
        let first = Party(.tenant, name: "Anna")
        var p = draft
        p.parties = [first, tenant("t2", "Beat")]
        var d = Defect(id: "d1")
        d.participantPositions[first.participantKey()] = TenantPosition(response: .normalWear)
        #expect(PdfExport.participantPositionLines(p, d, en) == ["Anna: \(en.tenantResponse(.normalWear))\n"])
    }

    @Test func theNotificationClausePrintsForAnEntryOnlyBecauseOnlyAnEntryEditsIt() {
        func transfer(_ kind: Kind) -> String {
            var p = draft
            p.kind = kind
            p.details.notificationClause = "Art. 12 du bail"
            p.details.notificationDays = "30"
            return (RecordContent.extraContent(record: p, strings: en).first { $0.title == en.actualTransfer }?.paragraphs ?? []).joined(separator: "\n")
        }
        #expect(transfer(.entry).contains("Art. 12 du bail"))
        #expect(transfer(.exit) == "")
    }

    @Test func aChipSpeaksTheSameWordsInHtmlUnlessItIsGivenOthers() {
        #expect(PdfExport.Chip("Photo annex").html == "Photo annex")
        #expect(PdfExport.Chip("Photo annex: Page 12", html: "Photo annex").html == "Photo annex")
    }

    /// Rooms.swift, which sets the annex chip, needs a PDF context; this drives the block it fills.
    @Test func theHtmlCopyOfAChipRowCarriesNoPageNumberIntoAFileWithoutPages() throws {
        let file = try temporaryRoot().appendingPathComponent("chips.html")
        let sink = try HtmlSink(url: file, language: .en, title: "t")
        PdfExport.Chips([PdfExport.Chip("Photos: 2"), PdfExport.Chip("Photo annex: Page 12", html: "Photo annex")]).html(sink)
        try sink.finish()
        let html = readText(file)
        #expect(html.contains("<li class=\"chip\">Photos: 2</li>"))
        #expect(html.contains("<li class=\"chip\">Photo annex</li>"))
        #expect(!html.contains("Page 12"))
    }
}
