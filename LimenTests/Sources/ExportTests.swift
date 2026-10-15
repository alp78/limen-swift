import Foundation
@testable import LimenKit
import PDFKit
import Testing
import UIKit
@testable import Limen

/// The document, end to end, on the record the Android instrumentation exports as its smoke: a
/// finalized exit in Vaud with every dossier component, one photographed finding, two ink files
/// and two delivery receipts. The result is a real PDF that PDFKit opens, with its pages counted.
@Suite struct ExportTests {
    @Test func pdfGlyphPixelsAppearAboveTheirBaselineAndLongTokensStayInsideTheColumn() throws {
        let sheet = try PdfExport.Sheet(s: Str(.en), reference: "pixel-test", total: 1)
        sheet.newPage()
        sheet.text("F", 200, 200, sheet.titleInk)
        let pass = try sheet.close()
        let provider = try #require(CGDataProvider(data: pass.data as CFData))
        let document = try #require(CGPDFDocument(provider))
        let page = try #require(document.page(at: 1))
        let width = 1240, height = 1754
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // A raw bitmap context uses PDF coordinates; its buffer rows are read top to bottom.
        context.scaleBy(x: CGFloat(width) / page.getBoxRect(.mediaBox).width, y: CGFloat(height) / page.getBoxRect(.mediaBox).height)
        context.drawPDFPage(page)
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        func darkPixels(yRange: Range<Int>) -> Int {
            var count = 0
            for y in yRange {
                for x in 195..<250 {
                    let index = (y * width + x) * 4
                    if pixels[index] < 100, pixels[index + 1] < 100, pixels[index + 2] < 100 { count += 1 }
                }
            }
            return count
        }
        #expect(darkPixels(yRange: 150..<200) > 100, "Upright F must lie above its baseline")
        #expect(darkPixels(yRange: 201..<250) == 0, "An inverted glyph falls below its baseline")
        for token in [String(repeating: "A9", count: 32), "https://example.invalid/" + String(repeating: "longpath", count: 20)] {
            let lines = sheet.wrapLines(token, sheet.body, 300)
            #expect(lines.count > 1)
            #expect(lines.joined() == token)
            #expect(lines.allSatisfy { sheet.body.width($0) <= 300 })
        }
    }

    private func evidence(_ file: URL, background: UIColor, text: String) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600), format: format).image { context in
            background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
            (text as NSString).draw(at: CGPoint(x: 60, y: 270), withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black])
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #require(image.pngData()).write(to: file)
    }

    private func professionalRecord(store: Store) throws -> HandoverProtocol {
        let photo = store.photoDir("pdf-smoke").appendingPathComponent("window-scratch.jpg")
        let tenantInk = store.signatureDir("pdf-smoke").appendingPathComponent("tenant-record.png")
        let landlordInk = store.signatureDir("pdf-smoke").appendingPathComponent("landlord-record.png")
        try evidence(photo, background: UIColor(red: 210 / 255, green: 180 / 255, blue: 150 / 255, alpha: 1), text: "WINDOW SCRATCH")
        try evidence(tenantInk, background: .white, text: "TENANT SIGNATURE")
        try evidence(landlordInk, background: .white, text: "LANDLORD SIGNATURE")

        var p = HandoverProtocol(id: "pdf-smoke", kind: .exit, createdEpochMs: 2)
        p.sessionRole = .landlord
        p.sessionName = "Test landlord"
        p.sessionIdentity.firstName = "Andrea"
        p.sessionIdentity.lastName = "Gerber"
        p.sessionIdentity.company = "Régie Professionnelle Exemple SA"
        p.sessionIdentity.street = "Rue de la Gare 44"
        p.sessionIdentity.postalCode = "1003"
        p.sessionIdentity.city = "Lausanne"
        p.sessionIdentity.phone = "+41215550199"
        p.controllerIdentity.organisation = "Régie Professionnelle Exemple SA"
        p.controllerIdentity.contactName = "Service protection des données"
        p.controllerIdentity.street = "Rue de la Gare 44"
        p.controllerIdentity.postalCode = "1003"
        p.controllerIdentity.city = "Lausanne"
        p.controllerIdentity.email = "privacy@example.invalid"
        p.controllerIdentity.phone = "+41215550199"
        p.address = "Test street 1"
        p.place = "1000 Test"
        p.objectCanton = .vd
        p.objectDetail = "3e étage, appartement gauche"
        p.handoverDate = "2026-08-18"
        p.handoverTime = "10:00"
        p.lastProtocolDate = "2024-08-18"
        p.parties = [
            Party(.tenant, name: "Test tenant", address: "Nouvelle adresse 9, 1200 Genève", representedBy: "Mandataire du locataire", phone: "+41791234567", email: "tenant@example.invalid"),
            Party(.landlord, name: "Régie Professionnelle Exemple SA", representedBy: "Andrea Gerber", phone: "+41215550199", email: "agency@example.invalid"),
        ]
        p.deposit.kind = .bankAccount
        p.deposit.amountChf = "5400.00"
        p.deposit.bank = "Banque Cantonale Vaudoise, Service professionnel des garanties de loyer"
        p.deposit.account = "CH93 0076 2011 6238 5295 7 / compte bloqué de garantie locative"
        p.contract.monthlyRentChf = "1800.00"
        p.contract.serviceChargesChf = "250.00"
        p.contract.conclusionDate = "2026-02-12"
        p.contract.startDate = "2026-03-01"
        p.contract.endDate = "2026-08-31"
        p.contract.noticeDate = "2026-05-29"
        p.meters.electricity1 = "48214.7"
        p.meters.electricity2 = "11802.2"
        p.meters.gas = "923.1"
        p.meters.water = "1210.3"
        p.meters.hotWater = "604.8"
        p.meters.heatingOil = "68%"
        p.rooms = [Room(id: "r1", kind: .room, inspected: true)]
        p.roomSetupComplete = true
        p.objects = [ObjectEntry(id: "o1", group: .other, groupLabel: "Supplied equipment", label: "Remote-controlled parking transmitter", roomId: "r1", note: "Serial no. PARK-2026-0044", inspected: true)]
        p.defects = [Defect(
            id: "d1", roomId: "r1", text: "Scratch 14 cm long on the lower north-facing window frame", photos: [photo.lastPathComponent],
            photoEvidence: [PhotoEvidence(photo.lastPathComponent, sha256: try ProtocolIntegrity.fileHash(photo), capturedEpochMs: 2, source: .camera)],
            chargedToTenant: true, fixBy: .landlord, fixDeadline: "2026-09-15", costNote: "Estimate requested; no debt acknowledged",
            reservation: "Tenant disputes responsibility", tenantResponse: .disputes, tenantComment: "Scratch was already visible before move-in"
        )]
        p.remarks = "Both parties reviewed the numbered finding and reservation before signing."
        p.chargesStatementBy = "2027-02-28"
        p.keys = [KeyCount(.apartment, count: 2), KeyCount(.mailbox, count: 1)]
        p.selfMadeKeys = true
        p.dossier = DossierCard.allCases
        p.keyTransfer = .allTransferred
        p.signatures = [
            Signature(.tenant, name: "Test tenant", plane: .record, file: tenantInk.lastPathComponent, contentRevision: 7),
            Signature(.landlord, name: "Andrea Gerber", plane: .record, file: landlordInk.lastPathComponent, contentRevision: 7),
        ]
        p.contentRevision = 7
        p.finalizedEpochMs = 3
        p.evidenceFingerprint = try ProtocolIntegrity.fingerprint(p, photoDir: store.photoDir(p.id), signatureDir: store.signatureDir(p.id))
        p.deliveryReceipts = [
            DeliveryReceipt(.tenant, epochMs: 1_787_043_600_000, method: .electronic, note: "secure tenant email"),
            DeliveryReceipt(.landlord, epochMs: 1_787_043_900_000, method: .inPerson, note: "agency copy"),
        ]
        p.deliveryMetadataEpochMs = 1_787_043_900_000
        return p
    }

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("limen-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theProfessionalRecordExportsAsAReadablePdfInEveryLanguage() throws {
        let root = try scratch()
        let store = Store(root: root)
        let record = try professionalRecord(store: store)
        #expect(ProtocolIntegrity.matches(record, photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id)))
        for lang in Lang.allCases {
            let exported = try PdfExport.export(record, Str(lang), photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id), folder: root)
            #expect(exported.bytes > 1_000, "\(lang)")
            let handle = try FileHandle(forReadingFrom: exported.url)
            let head = handle.readData(ofLength: 5)
            try handle.close()
            #expect(head == Data("%PDF-".utf8))
            let document = try #require(PDFDocument(url: exported.url))
            #expect(document.pageCount >= 2, "\(lang) has \(document.pageCount) pages")
            let text = document.string ?? ""
            #expect(text.contains("LIMEN-\(record.evidenceFingerprint.prefix(16))"), "\(lang) footer reference")
            #expect(text.contains("\(Str(lang).pdfPage) 1 / \(document.pageCount)"), "\(lang) page numbering")
            #expect(text.contains("Scratch 14 cm long"), "\(lang) finding text")
            let page = try #require(document.page(at: 0))
            let box = page.bounds(for: .mediaBox)
            #expect(abs(box.width - 595.276) < 0.01 && abs(box.height - 841.89) < 0.01)
        }
        let english = try PdfExport.export(record, Str(.en), photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id), folder: root)
        #expect(english.displayName.hasPrefix("limen-exit-"))
        #expect(english.displayName.hasSuffix(".pdf"))
    }

    @Test func completePreviewAndRetainedOutputsCarryEveryParticipantAndEscapedEvidence() throws {
        let root = try scratch()
        let store = Store(root: root)
        var record = try professionalRecord(store: store)
        record.parties[0].id = "tenant-one"
        record.parties[1].id = "landlord-one"
        record.parties[1].agency = "Example Agency"
        record.parties[1].authority = "Written mandate"
        var coTenant = Party(.tenant, name: "Second Tenant")
        coTenant.id = "tenant-two"
        record.parties.append(coTenant)
        record.details.reservations["tenant-one"] = "<script>alert('statement')</script>"
        record.details.reservations["tenant-two"] = "Independent reservation"
        record.signatures[0].participantId = record.parties[0].id
        record.signatures[0].name = record.parties[0].signerName()
        record.signatures[1].participantId = record.parties[1].id
        var coTenantOutcome = Signature(.tenant, name: coTenant.name, plane: .record, refused: true,
            reservation: "Independent reservation", contentRevision: record.contentRevision)
        coTenantOutcome.participantId = coTenant.id
        record.signatures.append(coTenantOutcome)
        record.details.readings = [MeterReading(id: "m1", label: "Water meter", identifier: "W42", value: "18", unit: "m³")]
        record.details.scopeNotes["Contract"] = "Lease unavailable on site"
        record.details.attachments = [SupportingDocument(id: "external", title: "Prior report", externalReference: "Held by both parties")]
        record.defects[0].participantPositions["tenant-two"] = TenantPosition(response: .normalWear, comment: "Independent position")
        record.evidenceFingerprint = try ProtocolIntegrity.fingerprint(record, photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id))
        for lang in Lang.allCases {
            let rendered = try PdfExport.document(record, Str(lang), photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id))
            let pdfText = try #require(PDFDocument(data: rendered.pdf)?.string)
            let html = String(decoding: rendered.html, as: UTF8.self)
            for phrase in ["Second Tenant", "Independent reservation", "Example Agency", "Written mandate", "Water meter", "Prior report", "Independent position"] {
                #expect(pdfText.contains(phrase), "\(lang): \(phrase)")
                #expect(html.contains(phrase), "\(lang): \(phrase)")
            }
            #expect(!html.contains("<script>"))
            #expect(html.contains("&lt;script&gt;"))
            #expect(html.contains("lang=\"\(lang.rawValue.lowercased())\""))
            let sample = root.appendingPathComponent("synthetic-\(lang.rawValue.lowercased())")
            try rendered.pdf.write(to: sample.appendingPathExtension("pdf"))
            try rendered.html.write(to: sample.appendingPathExtension("html"))
            print("LIMEN_DOCUMENT_SAMPLE \(sample.path) pages=\(rendered.pages)")
        }
        let copy = try PdfExport.exportRetained(record, Str(.en), store: store, publicFolder: root.appendingPathComponent("public"))
        record.exportHistory = [copy]
        try store.save(record)
        let retained = root.appendingPathComponent(copy.uri)
        #expect(try ProtocolIntegrity.fileHash(retained) == copy.sha256)
        try FileManager.default.removeItem(at: root.appendingPathComponent("public"))
        #expect(FileManager.default.fileExists(atPath: retained.path))
        #expect(store.load(record.id)?.exportHistory == [copy])
    }

    @Test func aDraftIsRefusedAndTamperedEvidenceIsRefused() throws {
        let root = try scratch()
        let store = Store(root: root)
        var record = try professionalRecord(store: store)
        #expect(throws: PdfExport.ExportError.notFinalized) {
            var draft = record
            draft.finalizedEpochMs = 0
            _ = try PdfExport.export(draft, Str(.en), photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id), folder: root)
        }
        try Data("swapped".utf8).write(to: store.photoDir(record.id).appendingPathComponent("window-scratch.jpg"))
        #expect(throws: PdfExport.ExportError.integrityMismatch) {
            _ = try PdfExport.export(record, Str(.en), photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id), folder: root)
        }
        record.evidenceFingerprint = ""
        #expect(!record.isFinalized())
    }

    @Test func draftPreviewNamesEveryMissingOutcomeWithoutClaimingFinalizationOrDepositRelease() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(root: root)
        var draft = try professionalRecord(store: store)
        draft.finalizedEpochMs = 0
        draft.evidenceFingerprint = ""
        draft.deposit.kind = .unknown
        draft.sessionRole = nil
        draft.parties[0].id = "tenant-present"
        draft.parties[1].id = "landlord-pending"
        var coTenant = Party(.tenant, name: "Co-tenant pending")
        coTenant.id = "tenant-pending"
        draft.parties.append(coTenant)
        draft.pendingRecordReservations[.landlord] = "Pending landlord reservation"
        draft.details.reservations[coTenant.id] = "Independent pending reservation"
        var outcome = try #require(draft.signatures.first)
        outcome.participantId = draft.parties[0].id
        let strings = Str(.en)
        func flattened(_ value: String) -> String { value.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

        // No recorded side on a legacy unilateral draft must not invent a tenant-only scope.
        // Both the drawn-ink and refusal variants must still name all outstanding outcomes.
        for oneSided in [false, true] {
            for refused in [false, true] {
                draft.oneSided = oneSided
                var signature = outcome
                signature.refused = refused
                if refused { signature.file = "" }
                draft.signatures = [signature]
                let document = try PdfExport.document(draft, strings, photoDir: store.photoDir(draft.id), signatureDir: store.signatureDir(draft.id))
                let pdf = flattened(try #require(PDFDocument(data: document.pdf)?.string))
                let html = String(decoding: document.html, as: UTF8.self)
                #expect(pdf.contains(strings.previewDraft.uppercased()))
                #expect(html.contains("<h1>\(strings.previewDraft)</h1>"))
                #expect(!pdf.contains(strings.pdfFinalized.uppercased()))
                #expect(!html.contains("<h2>\(strings.pdfFinalized)</h2>"))
                for text in [pdf, html] {
                    #expect(!text.contains(strings.fingerprint))
                    #expect(!text.contains("LIMEN-"))
                    #expect(!text.contains(strings.releaseTitle.uppercased()))
                    #expect(!text.contains(strings.releaseTitle))
                    #expect(!text.contains(strings.releaseBank))
                    #expect(!text.contains(strings.releaseInsurance))
                    for party in draft.parties.dropFirst() {
                        #expect(text.contains("\(strings.role(party.role)) · \(party.signerName()) · \(strings.notSigned)"))
                    }
                    #expect(text.contains("Pending landlord reservation"))
                    #expect(text.contains("Independent pending reservation"))
                }
                if refused {
                    #expect(pdf.contains(flattened(strings.refusedNote)))
                    #expect(html.contains(strings.refusedNote))
                } else {
                    #expect(html.contains("alt=\"\(outcome.name)\""))
                }
            }
        }
    }

    /// The Android matrix: every actor and both handovers finalize and export with two signatures.
    @Test func allThreeActorsCompleteEntryAndExitWithTwoSignaturesAndPdf() throws {
        let root = try scratch()
        let store = Store(root: root)
        for actor in ["tenant", "landlord", "agency"] {
            for kind in Kind.allCases {
                let id = "matrix-\(actor)-\(kind.rawValue.lowercased())"
                let photo = store.photoDir(id).appendingPathComponent("finding.jpg")
                let tenantInk = store.signatureDir(id).appendingPathComponent("tenant-record.png")
                let landlordInk = store.signatureDir(id).appendingPathComponent("landlord-record.png")
                try evidence(photo, background: .lightGray, text: "\(actor) \(kind.rawValue) DEFECT")
                try evidence(tenantInk, background: .white, text: "TENANT")
                try evidence(landlordInk, background: .white, text: "LANDLORD")
                var draft = HandoverProtocol(id: id, kind: kind, createdEpochMs: 20)
                draft.sessionRole = actor == "tenant" ? .tenant : .landlord
                draft.sessionName = "\(actor) operator"
                // The two identities the Android matrix carries. Without them the three actors
                // collapsed to two record shapes, because the agency differs from the private
                // landlord only in the company on its session identity and the organisation on
                // its controller identity, and neither reached the exported document.
                var operatorIdentity = SessionIdentity()
                operatorIdentity.firstName = actor.prefix(1).uppercased() + actor.dropFirst()
                operatorIdentity.lastName = "Operator"
                operatorIdentity.company = actor == "agency" ? "Matrix Agency SA" : ""
                operatorIdentity.street = "Testweg 8"
                operatorIdentity.postalCode = "5000"
                operatorIdentity.city = "Aarau"
                operatorIdentity.phone = "+41625550101"
                draft.sessionIdentity = operatorIdentity
                var controller = ControllerIdentity()
                controller.organisation = actor == "agency" ? "Matrix Agency SA" : "Matrix operator"
                controller.contactName = "\(actor) operator"
                controller.email = "\(actor)@example.invalid"
                draft.controllerIdentity = controller
                draft.address = "Testweg 10"
                draft.place = "5000 Aarau"
                draft.objectCanton = .ag
                draft.handoverDate = "2026-08-21"
                draft.handoverTime = "09:30"
                draft.legalOverlay = LegalOverlayRecord().withStatus(.leaseAndLocalTiming, .confirmed)
                draft.parties = [
                    Party(.tenant, name: "Matrix Tenant", representedBy: "Tenant proxy", email: "tenant@example.invalid"),
                    Party(.landlord, name: actor == "agency" ? "Matrix Agency SA" : "Matrix Landlord", representedBy: actor == "agency" ? "Agency Operator" : "", email: "landlord@example.invalid"),
                ]
                for index in draft.parties.indices where !draft.parties[index].representedBy.isBlank { draft.parties[index].authority = "Mandate shown" }
                draft.contract.conclusionDate = "2026-07-01"
                draft.contract.startDate = "2026-08-01"
                draft.rooms = [Room(id: "r1", kind: .room, inspected: true)]
                draft.roomSetupComplete = true
                draft.defects = [Defect(id: "d1", roomId: "r1", text: "Two-centimetre paint chip beside the inner door handle", photos: ["finding.jpg"], photoEvidence: [PhotoEvidence("finding.jpg", sha256: try ProtocolIntegrity.fileHash(photo), capturedEpochMs: 21, source: .camera)], reservation: "Recorded without accepting a debt", tenantResponse: kind == .exit ? .disputes : .notStated, tenantComment: kind == .exit ? "Already present at entry" : "")]
                draft.dossier = [.keys]
                draft.keyTransfer = .noPhysicalKeys
                draft.signatures = [
                    Signature(.tenant, name: "Matrix Tenant", plane: .record, file: "tenant-record.png", contentRevision: 3),
                    Signature(.landlord, name: "Matrix Landlord", plane: .record, file: "landlord-record.png", contentRevision: 3),
                ]
                draft.contentRevision = 3
                let issues = CompletionRules.protocolCompletionIssues(draft, requiredRoles: [.tenant, .landlord], photoDir: store.photoDir(id), signatureDir: store.signatureDir(id))
                #expect(issues.isEmpty, "\(actor) \(kind): \(issues)")
                var frozen = draft
                frozen.finalizedEpochMs = 30
                frozen.evidenceFingerprint = try ProtocolIntegrity.fingerprint(frozen, photoDir: store.photoDir(id), signatureDir: store.signatureDir(id))
                let exported = try PdfExport.export(frozen, Str(.en), photoDir: store.photoDir(id), signatureDir: store.signatureDir(id), folder: root)
                #expect(exported.bytes > 1_000, "PDF too small for \(actor) \(kind)")
                // A byte count says the document rendered, not that it says who compiled it: the
                // line naming the party is the one thing that differs between the three actors.
                let text = try #require(PDFDocument(url: exported.url)?.string)
                #expect(text.contains(Str(.en).compiledBy), "no compiled-by line for \(actor) \(kind)")
                #expect(text.contains("Matrix Tenant"), "the tenant is not named for \(actor) \(kind)")
                #expect(text.contains(actor == "agency" ? "Matrix Agency SA" : "Matrix Landlord"), "the landlord side is not named for \(actor) \(kind)")
            }
        }
    }

    /// The model's own walk on a scratch store: a session started from the form, a room, a
    /// finding, ink, the freeze, and the exported document, without a screen in between.
    @Test @MainActor func theModelWalksASessionFromTheFormToTheDocument() throws {
        let root = try scratch()
        let prefs = try #require(UserDefaults(suiteName: "limen-tests-\(UUID().uuidString)"))
        let model = LimenModel(prefs: prefs, root: root)
        var identity = SessionIdentity()
        identity.firstName = "Ada"
        identity.lastName = "Lovelace"
        identity.street = "Rue du Simplon"
        identity.flatNumber = "12"
        identity.postalCode = "1006"
        identity.city = "Lausanne"
        identity.phone = "021 729 71 10"
        model.startNewSession(role: .tenant, identity: identity, kind: .exit)
        let opened = try #require(model.working)
        #expect(opened.parties[0].name == "Ada Lovelace")
        #expect(opened.parties[0].phone == "+41217297110")
        #expect(opened.parties[0].address == "Rue du Simplon 12, 1006 Lausanne")
        model.edit { p in
            var next = p
            next.address = "Rue Test 1"
            next.place = "1000 Lausanne"
            next.objectCanton = .ag
            next.handoverTime = "10:00"
            next.parties[1].name = "Landlord"
            return next
        }
        model.edit { p in
            var next = p
            next.legalOverlay = p.legalOverlay.withStatus(.leaseAndLocalTiming, .confirmed)
            next.keyTransfer = .noPhysicalKeys
            next.keys = p.keys.map { var k = $0; k.count = 0; return k }
            return next
        }
        model.setInitialRooms([.hall, .kitchen])
        #expect(model.working?.rooms.count == 2)
        let hall = try #require(model.working?.rooms.first)
        model.openDefect(hall.id, item: .floor)
        let defectId = try #require(model.editingDefectId)
        model.updateDefect(defectId) { var d = $0; d.text = "Scratch"; return d }
        model.closeDefect()
        #expect(model.working?.defects.count == 1)
        model.setRoomInspected(hall.id, true)
        model.setRoomInspected(try #require(model.working?.rooms[1].id), true)
        let ink = try #require(UIImage(systemName: "signature")?.pngData())
        model.keepSignature(.tenant, plane: .record, png: ink)
        model.refuseSignature(.landlord, plane: .record)
        #expect(model.completionIssues().isEmpty, "\(model.completionIssues())")
        model.flush()
        #expect(model.store.load(opened.id)?.isSigned() == true)
    }
}
