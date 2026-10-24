import Foundation
import Testing
@testable import LimenKit

/// Guards the one thing a finalized record cannot survive.
///
/// `ProtocolIntegrity` canonicalizes with defaults spelt out, so a new field written without the
/// `never` mark appears in the canonical JSON of every record ever written, moves their
/// fingerprints, and locks them out of export forever. The store's `schema` field cannot warn us:
/// it is never written to disk, because the store omits defaulted fields.
///
/// The pinned fingerprint is the Android suite's own: the same record, the same ink bytes, the
/// same hex. It is the proof that a record signed on either phone verifies on the other.
@Suite struct LegacyCompatTests {
    private static let goldenFingerprint = "9BCDDF82B00F72B599EF5188085D846CC69820F8DEFC7AE7CC35860246C28275"
    private static let goldenFinalizedFingerprint = "2853CCC553B79B76EAFF7B416E4D5F2C4222297682606D9615F38EEBFB9D50B7"

    private func v2Record() -> HandoverProtocol {
        var p = HandoverProtocol(id: "old", kind: .entry, createdEpochMs: 1)
        p.address = "Rue du Simplon 12"
        p.place = "1006 Lausanne"
        // Written out rather than taken from Templates. A fixture that reads the app's own
        // catalogue moves whenever the catalogue does, and a pinned fingerprint that moves for
        // that reason teaches everyone to paste the new value, which is how the guard dies.
        p.rooms = [Room(id: "r1", kind: .kitchen, items: [RoomItem(.floor, grade: .ok), RoomItem(.walls, grade: .ok)])]
        return p
    }

    /// Every nested type, instantiated: a field only reaches the canonical JSON if something
    /// instantiates the type that carries it.
    private func everyNestedType() -> HandoverProtocol {
        var p = v2Record()
        p.defects = [Defect(id: "d1", roomId: "r1", text: "Stain")]
        p.objects = [ObjectEntry(id: "o1", group: .appliance)]
        var contract = Contract()
        contract.monthlyRentChf = "1850"
        p.contract = contract
        p.parties = [Party(.tenant, name: "Marie Rouiller")]
        p.keys = [KeyCount(.apartment, count: 3)]
        var deposit = Deposit()
        deposit.kind = .bankAccount
        deposit.amountChf = "5550"
        p.deposit = deposit
        var meters = Meters()
        meters.electricity1 = "48214.7"
        p.meters = meters
        p.signatures = [Signature(.tenant, plane: .record, file: "tenant-record.png")]
        return p
    }

    /// What every record finalized since 1.2.0 carries on top of that: the starter's identity, the
    /// controller block and the details, with the legal snapshot that finalization always freezes
    /// into them, and the canton, the legal overlay and a tenant's position on a finding, which
    /// every such record also carries. All of them are `never`-encoded at their defaults, so a
    /// fixture that leaves them out never invokes their writers, and a field added to any of them
    /// without the mark would move the fingerprint of every such record while the pin on
    /// `everyNestedType` stayed green.
    ///
    /// `reviewRevision`, `participantNoticeShown`, `addressCountry`, `usesSwissAddress` and
    /// `phoneRegion` are left at their declared defaults on purpose: the pin only notices a changed
    /// literal default when the fixture takes it. The strings carry accents, quotes, a newline and
    /// a surrogate pair, because every real French, German or Italian record does.
    private func finalizedRecord() -> HandoverProtocol {
        var p = everyNestedType()
        p.objectCanton = .vd
        p.romandFrameworkInLease = true
        var overlay = LegalOverlayRecord()
        overlay.checks[.initialRentForm] = .confirmed
        overlay.checks[.vaudExitReadiness] = .missingOrDisputed
        overlay.note = "Formule officielle remise avec le bail"
        overlay.ruleSetId = "ch-tenancy-2026.2"
        overlay.notes[.vaudExitReadiness] = "Convocation en attente, voir \\ le dossier"
        p.legalOverlay = overlay
        var defect = Defect(id: "d1", roomId: "r1", text: "Stain")
        defect.participantPositions["tenant-1"] = TenantPosition(response: .disputes, comment: "Existait à l’entrée")
        p.defects = [defect]
        var identity = SessionIdentity()
        identity.firstName = "Hélène"
        identity.lastName = "Müller-Rochat"
        identity.company = "Régie du Léman SA"
        identity.street = "Rue du Simplon"
        identity.flatNumber = "12 b"
        identity.postalCode = "1006"
        identity.city = "Lausanne"
        identity.phone = "+41 21 555 01 23"
        p.sessionIdentity = identity
        var controller = ControllerIdentity()
        controller.organisation = "Régie du Léman SA"
        controller.contactName = "Hélène Müller-Rochat"
        controller.street = "Rue du Simplon 12 b"
        controller.postalCode = "1006"
        controller.city = "Lausanne"
        controller.email = "helene@regie.example"
        controller.phone = "+41 21 555 01 23"
        p.controllerIdentity = controller
        var details = RecordDetails()
        details.municipality = "Lausanne"
        details.district = "Lausanne"
        details.habitableRooms = "3.5"
        details.actualTransferDate = "2026-10-01"
        details.actualTransferTime = "14:30"
        details.notificationDays = "30"
        details.notificationClause = "Art. 12 du bail"
        details.scopeNotes["r1"] = "Armoire fermée à clé,\nnon inspectée"
        var overview = PhotoEvidence("kitchen-overview.jpg", sha256: "ab12cd34", capturedEpochMs: 1_760_000_000_000, source: .camera)
        overview.importedEpochMs = 1_760_000_100_000
        details.roomPhotos["r1"] = [overview]
        details.readings = [MeterReading(id: "m1", label: "Électricité", identifier: "CH-1234", value: "48214.7", unit: "kWh", date: "2026-10-01", time: "14:40",
                                         note: "Compteur au sous-sol 🔑", photos: [PhotoEvidence("meter-electricity.jpg", source: .gallery)])]
        details.accessDevices = [AccessDevice(id: "a1", label: "Badge", identifier: "B-77", expected: 2, transferred: 2, note: "Remis en main propre")]
        details.attachments = [SupportingDocument(id: "doc1", kind: .lease, title: "Bail à loyer", file: "lease.pdf", sha256: "ef56ab78", bytes: 2048,
                                                  importedEpochMs: 1_760_000_200_000, externalReference: "Réf. 2026\\17")]
        details.followUps = [FollowUp(id: "f1", description: "Remplacer le joint", discoveredDate: "2026-10-01", notifiedDate: "2026-10-02",
                                      recipient: "Régie", method: "Courriel", deadline: "2026-11-01", done: true)]
        details.estimates["d1"] = ReplacementEstimate(replacementChf: "1200", ageYears: "6", lifeYears: "15", basis: "Table de durée de vie", date: "2026-10-01")
        details.reservations["tenant-1"] = "Je conteste l’état du \"sol\""
        // The literal, not the app's constant: that moves with every legal catalogue release, and
        // a pin that fails for it teaches the habit of pasting a new value.
        details.legalSnapshot = LegalSnapshot(ruleSetId: "ch-tenancy-2026.2", profile: "VD", initialRentFormRule: "Formule officielle exigée",
                                              requirements: [.initialRentForm, .vaudExitReadiness], sources: ["https://www.vd.ch/exemple"])
        details.understoodLanguage = "fr"
        p.details = details
        return p
    }

    private func canonical(_ p: HandoverProtocol) -> String { ProtocolJSON.encode(p, encodeDefaults: true).compact }

    @Test func everyNestedSerializableTypeIsActuallyInstantiatedByTheFixture() {
        let json = canonical(everyNestedType())
        for key in ["\"defects\"", "\"objects\"", "\"contract\"", "\"parties\"", "\"keys\"", "\"signatures\""] {
            #expect(json.contains(key), "the fixture must instantiate \(key) for the absence tests to mean anything")
        }
    }

    @Test func topLevelFieldsAddedAfterTheDossierNeverReachTheCanonicalJson() {
        let json = canonical(v2Record())
        for key in ["objects", "contract", "dossier", "dossierChosen", "amendedFromFingerprint", "controllerIdentity", "roomSetupComplete",
                    "deliveryMetadataEpochMs", "objectCanton", "romandFrameworkInLease", "legalOverlay", "unilateralReason", "unilateralNote",
                    "keyTransfer", "keyTransferNote", "pendingRecordReservations", "inspected"] {
            #expect(!json.contains("\"\(key)\""), "\(key) must not appear in a record that does not use it")
        }
    }

    @Test func nestedFieldsNeverReachTheCanonicalJsonEitherWhenTheirTypeIsPresent() {
        let json = canonical(everyNestedType())
        for key in ["itemLabel", "objectId", "itemId", "conclusionDate", "inspected"] {
            #expect(!json.contains("\"\(key)\""), "\(key) must not appear even though its type is on the record")
        }
    }

    @Test func theCanonicalTextSpellsTheFieldsInDeclarationOrderWithDefaultsOut() {
        let json = canonical(v2Record())
        #expect(json.hasPrefix("{\"schema\":2,\"id\":\"old\",\"kind\":\"Entry\",\"style\":\"Binary\",\"address\":\"Rue du Simplon 12\",\"place\":\"1006 Lausanne\",\"objectDetail\":\"\",\"handoverDate\":\"\",\"handoverTime\":\"\",\"lastProtocolDate\":\"\",\"createdEpochMs\":1,\"parties\":[],\"deposit\":{\"kind\":\"None\""))
        #expect(json.contains("\"rooms\":[{\"id\":\"r1\",\"kind\":\"Kitchen\",\"name\":\"\",\"items\":[{\"key\":\"Floor\",\"label\":\"\",\"grade\":\"Ok\"},{\"key\":\"Walls\",\"label\":\"\",\"grade\":\"Ok\"}],\"keysCount\":0,\"freshPaintedWalls\":false,\"freshPaintedWoodwork\":false,\"newFloor\":false,\"fixtures\":[]}]"))
        #expect(json.hasSuffix("\"deliveryReceipts\":[],\"exportedEpochMs\":0}"))
    }

    @Test func aDefectWithNoItemWritesItemAsNullInTheCanonicalText() {
        let json = canonical(everyNestedType())
        #expect(json.contains("\"defects\":[{\"id\":\"d1\",\"roomId\":\"r1\",\"item\":null,\"text\":\"Stain\","))
    }

    @Test func aRecordWithoutObjectsFingerprintsExactlyAsItAlwaysDid() throws {
        let root = try temporaryRoot()
        let photos = try makeDir(root.appendingPathComponent("photos"))
        let ink = try makeDir(root.appendingPathComponent("ink"))
        try writeText("original photo bytes", to: photos.appendingPathComponent("wall.jpg"))

        var old = v2Record()
        old.defects = [Defect(id: "d1", roomId: "r1", text: "Stain", photos: ["wall.jpg"])]
        old.finalizedEpochMs = 12
        var frozen = old
        frozen.evidenceFingerprint = try ProtocolIntegrity.fingerprint(old, photoDir: photos, signatureDir: ink)
        #expect(ProtocolIntegrity.matches(frozen, photoDir: photos, signatureDir: ink))

        // Setting the new fields to their defaults explicitly must change nothing at all.
        var restated = frozen
        restated.objects = []
        restated.contract = Contract()
        restated.dossier = []
        restated.dossierChosen = false
        restated.amendedFromFingerprint = ""
        #expect(ProtocolIntegrity.matches(restated, photoDir: photos, signatureDir: ink))
    }

    /// The fingerprint of a fixed record, pinned to the Android value. Do not "fix" it by pasting
    /// a new value: a moved fingerprint means every record already signed on either phone can no
    /// longer be exported here, and the serializer is what has to change instead.
    @Test func theCanonicalFingerprintOfAFixedRecordHasNotMoved() throws {
        let root = try temporaryRoot()
        let photos = try makeDir(root.appendingPathComponent("photos"))
        let ink = try makeDir(root.appendingPathComponent("ink"))
        try writeText("fixed ink bytes", to: ink.appendingPathComponent("tenant-record.png"))
        let fingerprint = try ProtocolIntegrity.fingerprint(everyNestedType(), photoDir: photos, signatureDir: ink)
        #expect(fingerprint == Self.goldenFingerprint)
    }

    @Test func theFinalizedFixtureReachesTheWritersOfTheTypesThatFinalizationFills() {
        // The guard on the pin below: a fixture that drops one of these goes vacuous without failing.
        let json = canonical(finalizedRecord())
        for key in ["\"sessionIdentity\"", "\"addressCountry\"", "\"phoneRegion\"", "\"company\"",
                    "\"controllerIdentity\"", "\"organisation\"",
                    "\"details\"", "\"reviewRevision\"", "\"participantNoticeShown\"", "\"roomPhotos\"",
                    "\"importedEpochMs\"", "\"readings\"", "\"accessDevices\"", "\"attachments\"",
                    "\"followUps\"", "\"estimates\"", "\"legalSnapshot\"", "\"checkedOn\"",
                    "\"objectCanton\"", "\"romandFrameworkInLease\"", "\"legalOverlay\"", "\"notes\"", "\"participantPositions\""] {
            #expect(json.contains(key), "the finalized fixture must instantiate \(key)")
        }
        // A backslash is escaped in the canonical form, and the strings of a real record carry one.
        #expect(json.contains("\\\\"))
    }

    /// The same pin for a record as 1.2.0 and later finalize it, the Android suite's own hex. The
    /// pin above covers a record whose three `never`-encoded blocks sit at their defaults, so it
    /// cannot see them; this one can.
    @Test func theCanonicalFingerprintOfAFixedFinalizedRecordHasNotMoved() throws {
        let root = try temporaryRoot()
        let photos = try makeDir(root.appendingPathComponent("photos"))
        let ink = try makeDir(root.appendingPathComponent("ink"))
        try writeText("fixed ink bytes", to: ink.appendingPathComponent("tenant-record.png"))
        for name in ["kitchen-overview.jpg", "meter-electricity.jpg", "lease.pdf"] {
            try writeText("fixed bytes of \(name)", to: photos.appendingPathComponent(name))
        }
        #expect(try ProtocolIntegrity.fingerprint(finalizedRecord(), photoDir: photos, signatureDir: ink) == Self.goldenFinalizedFingerprint)
    }

    @Test func objectPhotosAreEvidenceToo() throws {
        let root = try temporaryRoot()
        let photos = try makeDir(root.appendingPathComponent("photos"))
        let ink = try makeDir(root.appendingPathComponent("ink"))
        try writeText("original photo bytes", to: photos.appendingPathComponent("fridge.jpg"))

        var draft = v2Record()
        draft.objects = [ObjectEntry(id: "o1", group: .appliance, catalogue: Appliance.fridge.rawValue, photos: ["fridge.jpg"])]
        draft.finalizedEpochMs = 12
        var frozen = draft
        frozen.evidenceFingerprint = try ProtocolIntegrity.fingerprint(draft, photoDir: photos, signatureDir: ink)
        #expect(ProtocolIntegrity.matches(frozen, photoDir: photos, signatureDir: ink))

        try writeText("swapped photo bytes", to: photos.appendingPathComponent("fridge.jpg"))
        #expect(!ProtocolIntegrity.matches(frozen, photoDir: photos, signatureDir: ink))
    }

    @Test func anOlderRecordAnswersItsDossierFromItsContent() {
        var old = v2Record()
        old.deposit.kind = .insurance
        old.deposit.amountChf = "4500"
        old.meters.electricity1 = "48214.7"
        old.remarks = "Ne vaut pas reconnaissance de dette."
        #expect(old.dossierCards() == [.deposit, .meters, .notes])
        #expect(old.carries(.deposit))
        #expect(!old.carries(.keys))
    }

    @Test func anEmptyOlderRecordCarriesNoComponents() {
        #expect(v2Record().dossierCards().isEmpty)
    }

    @Test func anExplicitDossierOverridesWhatTheContentSuggests() {
        var edited = v2Record()
        edited.deposit.kind = .insurance
        edited.deposit.amountChf = "4500"
        edited.dossier = [.keys]
        #expect(edited.dossierCards() == [.keys])
        #expect(!edited.carries(.deposit))
    }

    @Test func onlyOlderRoomsCarryTheItemGrid() {
        #expect(v2Record().rooms[0].hasLegacyGrid)
        #expect(!Room(id: "r9", kind: .bathroom).hasLegacyGrid)
    }

    @Test func removingTheLastComponentIsRememberedRatherThanDerivedBack() {
        var stripped = v2Record()
        stripped.oneSided = true
        stripped.remarks = ""
        stripped.dossier = []
        stripped.dossierChosen = true
        #expect(stripped.dossierCards().isEmpty)
        #expect(!stripped.carries(.notes))
    }

    @Test func aRecordThatChoseItsComponentsBeforeTheFlagExistedStillAnswersFromItsList() {
        var older = v2Record()
        older.dossier = [.keys]
        older.dossierChosen = false
        #expect(older.dossierCards() == [.keys])
    }

    @Test func aFindingIsUntouchedOnlyWhileItCarriesNothingButItsPlace() {
        let shell = Defect(id: "d1", roomId: "r1", item: .floor)
        #expect(shell.isUntouched)
        var d = shell
        d.text = "Stain"
        #expect(!d.isUntouched)
        d = shell
        d.photos = ["a.jpg"]
        #expect(!d.isUntouched)
        d = shell
        d.chargedToTenant = true
        #expect(!d.isUntouched)
        d = shell
        d.fixBy = .tenant
        #expect(!d.isUntouched)
        d = shell
        d.fixDeadline = "2026-09-01"
        #expect(!d.isUntouched)
        d = shell
        d.costNote = "CHF 120"
        #expect(!d.isUntouched)
        d = shell
        d.reservation = "conteste"
        #expect(!d.isUntouched)
        d = shell
        d.tenantResponse = .disputes
        #expect(!d.isUntouched)
        d = shell
        d.tenantComment = "already at entry"
        #expect(!d.isUntouched)
    }
}
