import Foundation
import LimenKit
import PDFKit
import Testing
import UIKit
@testable import Limen

/// The document, end to end, on the record the Android instrumentation exports as its smoke: a
/// finalized exit in Vaud with every dossier component, one photographed finding, two ink files
/// and two delivery receipts. The result is a real PDF that PDFKit opens, with its pages counted.
@Suite struct ExportTests {
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
            let head = try #require(FileHandle(forReadingFrom: exported.url).readData(ofLength: 5))
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

    @Test func aDraftIsRefusedAndTamperedEvidenceIsRefused() throws {
        let root = try scratch()
        let store = Store(root: root)
        var record = try professionalRecord(store: store)
        #expect(throws: PdfExport.ExportError.notFinalized) {
            var draft = record
            draft.finalizedEpochMs = 0
            try PdfExport.export(draft, Str(.en), photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id), folder: root)
        }
        try Data("swapped".utf8).write(to: store.photoDir(record.id).appendingPathComponent("window-scratch.jpg"))
        #expect(throws: PdfExport.ExportError.integrityMismatch) {
            try PdfExport.export(record, Str(.en), photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id), folder: root)
        }
        record.evidenceFingerprint = ""
        #expect(!record.isFinalized())
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
