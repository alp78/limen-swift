import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import Limen
@testable import LimenKit

/// The 1.2.5 handoff's measurements on real photographs: a finalized record carrying up to thirty
/// of them, rendered as the preview and the export both render it, then backed up with and
/// without JPEG XL repacking, restored, and every recorded hash checked on the other side.
///
/// Runs only when LIMEN_MEASURE_PHOTOS names a folder of JPEGs, absolute on the simulator or
/// relative to the app's Documents on the phone, and leaves its files where LIMEN_MEASURE_OUT
/// says. With LIMEN_MEASURE_KEEP=1, and only under the audit identity, the record is also saved
/// into the app's own store so the preview can be photographed on the device.
@Suite struct MeasurementTests {
    private let environment = ProcessInfo.processInfo.environment

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIMEN_MEASURE_PHOTOS"] != nil))
    func thirtyPhotographsThroughTheDocumentAndTheBackup() throws {
        let photosDir = try resolve(#require(environment["LIMEN_MEASURE_PHOTOS"]))
        let files = Array(try FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil)
            .filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(30))
        try #require(!files.isEmpty, "no JPEG in \(photosDir.path)")
        let sourceBytes = try files.reduce(0) { $0 + (try size($1)) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("limen-measure-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = Store(root: root.appendingPathComponent("store"))
        let record = try measurementRecord(store: store, photos: files)
        let plates = Report.plates(record)
        #expect(plates.count == files.count)

        // The document, as the preview and the export both render it.
        let s = Str(.fr)
        let clock = ContinuousClock()
        var rendered: PdfExport.Document?
        let exportTime = try clock.measure {
            rendered = try PdfExport.document(record, s, photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id),
                                              scratch: root.appendingPathComponent("scratch"))
        }
        let document = try #require(rendered)
        print("LIMEN_MEASURE_FOOTPRINT after-export peak=\(Self.footprintPeak()) now=\(Self.footprintNow())")
        let pdfBytes = try size(document.pdf)
        let htmlBytes = try size(document.html)
        let pdf = try #require(PDFDocument(url: document.pdf))
        #expect(pdf.pageCount == document.pages)
        // The request's stop condition: a PDF of thirty photographs over 10 MB is reported, not shipped.
        #expect(pdfBytes <= 10 * 1024 * 1024, "the PDF weighs \(pdfBytes) bytes")

        // The backup, repacked and not, and the repacked one restored with every hash checked.
        let repacked = root.appendingPathComponent("backup-jxl.limen")
        let repackTime = try clock.measure { try store.exportArchive(password: "mesure", to: repacked) }
        print("LIMEN_MEASURE_FOOTPRINT after-repacked-backup peak=\(Self.footprintPeak()) now=\(Self.footprintNow())")
        let asJpeg = root.appendingPathComponent("backup-jpeg.limen")
        let jpegTime = try clock.measure { try store.exportArchive(password: "mesure", to: asJpeg, packer: nil) }
        print("LIMEN_MEASURE_FOOTPRINT after-jpeg-backup peak=\(Self.footprintPeak()) now=\(Self.footprintNow())")
        let restoredStore = Store(root: root.appendingPathComponent("restored"))
        var result: ArchiveImportResult?
        let restoreTime = try clock.measure { result = try restoredStore.importArchive(password: "mesure", from: repacked) }
        #expect(try #require(result).imported == 1)
        print("LIMEN_MEASURE_FOOTPRINT after-restore peak=\(Self.footprintPeak()) now=\(Self.footprintNow())")
        for plate in plates {
            #expect(try ProtocolIntegrity.fileHash(restoredStore.photoDir(record.id).appendingPathComponent(plate.file)) == plate.sha256, "\(plate.file)")
        }

        #if targetEnvironment(simulator)
        let device = "simulator"
        #else
        let device = "device"
        #endif
        #if DEBUG
        let configuration = "Debug"
        #else
        let configuration = "Release"
        #endif
        let metrics: [String: Any] = [
            "photos": files.count, "sourceBytes": sourceBytes, "pdfBytes": pdfBytes, "htmlBytes": htmlBytes, "pages": document.pages,
            "exportSeconds": seconds(exportTime), "backupRepackedBytes": try size(repacked), "backupRepackedSeconds": seconds(repackTime),
            "backupJpegBytes": try size(asJpeg), "backupJpegSeconds": seconds(jpegTime), "restoreRepackedSeconds": seconds(restoreTime),
            "footprintPeakBytes": Self.footprintPeak(), "where": device, "configuration": configuration,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        let json = try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys])
        print("LIMEN_MEASURE \(String(decoding: json, as: UTF8.self))")

        if let out = environment["LIMEN_MEASURE_OUT"] {
            let dir = try resolve(out)
            for (source, name) in [(document.pdf, "mesure-30.pdf"), (document.html, "mesure-30.html"), (repacked, "mesure-30-jxl.limen"), (asJpeg, "mesure-30-jpeg.limen")] {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
                try FileManager.default.copyItem(at: source, to: dir.appendingPathComponent(name))
            }
            try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]).write(to: dir.appendingPathComponent("measure.json"))
            print("LIMEN_MEASURE_OUT \(dir.path)")
        }
        document.discard()

        // Into the app's own store, for the preview on the device; never into the production identity.
        if environment["LIMEN_MEASURE_KEEP"] == "1", Bundle.main.bundleIdentifier?.hasSuffix(".audit") == true {
            let live = Store(root: AppFiles.support)
            live.delete(record.id)
            for (from, to) in [(store.photoDir(record.id), live.photoDir(record.id)), (store.signatureDir(record.id), live.signatureDir(record.id))] {
                try? FileManager.default.removeItem(at: to)
                try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: from, to: to)
            }
            try live.save(record)
            print("LIMEN_MEASURE_KEPT \(record.id)")
        }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - The record

    /// A four-room flat walked for an entry: six rooms photographed, ten findings with eighteen
    /// photographs between them, two supplied objects with three, three meters with one each.
    /// The slots are filled in that order with whatever photographs the folder holds.
    private func measurementRecord(store: Store, photos: [URL]) throws -> HandoverProtocol {
        let id = "mesure-30"
        let photoDir = store.photoDir(id)
        let inkDir = store.signatureDir(id)
        try FileManager.default.createDirectory(at: photoDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: inkDir, withIntermediateDirectories: true)

        var p = HandoverProtocol(id: id, kind: .entry, createdEpochMs: 1_792_564_200_000)
        p.sessionRole = .landlord
        p.sessionName = "Régie de la Mesure SA"
        p.sessionIdentity.firstName = "Claire"
        p.sessionIdentity.lastName = "Exemple"
        p.sessionIdentity.company = "Régie de la Mesure SA"
        p.sessionIdentity.street = "Rue de la Gare 44"
        p.sessionIdentity.postalCode = "1003"
        p.sessionIdentity.city = "Lausanne"
        p.sessionIdentity.phone = "+41215550199"
        p.address = "Avenue de la Mesure 30"
        p.place = "1003 Lausanne"
        p.objectCanton = .vd
        p.objectDetail = "2e étage, appartement de 4 pièces"
        p.handoverDate = "2026-10-21"
        p.handoverTime = "09:30"
        p.parties = [
            Party(.tenant, name: "Jean Locataire", phone: "+41791234567", email: "jean@example.invalid"),
            Party(.landlord, name: "Régie de la Mesure SA", representedBy: "Claire Exemple", phone: "+41215550199", email: "regie@example.invalid"),
        ]
        p.deposit.kind = .bankAccount
        p.deposit.amountChf = "4500.00"
        p.deposit.bank = "Banque Cantonale Vaudoise"
        p.deposit.account = "CH93 0076 2011 6238 5295 7"
        p.contract.monthlyRentChf = "1500.00"
        p.contract.serviceChargesChf = "200.00"
        p.contract.conclusionDate = "2026-09-01"
        p.contract.startDate = "2026-11-01"
        let rooms: [(id: String, kind: RoomKind)] = [("r1", .kitchen), ("r2", .bathroom), ("r3", .livingRoom), ("r4", .bedroom), ("r5", .hall), ("r6", .balcony)]
        p.rooms = rooms.map { Room(id: $0.id, kind: $0.kind, inspected: true) }
        p.roomSetupComplete = true
        struct Finding {
            let room: String
            let text: String
            let response: TenantResponse
            init(_ room: String, _ text: String, _ response: TenantResponse) { (self.room, self.text, self.response) = (room, text, response) }
        }
        let findings: [Finding] = [
            Finding("r1", "Rayure de 14 cm sur le plan de travail, à gauche de la plaque de cuisson", .disputes),
            Finding("r1", "Joint silicone noirci sur toute la longueur de l’évier", .agrees),
            Finding("r2", "Émail de la baignoire éclaté près de la bonde, 2 cm", .existingAtEntry),
            Finding("r2", "Porte-serviettes descellé du mur, deux chevilles manquantes", .notStated),
            Finding("r3", "Parquet marqué par les pieds d’un meuble sous la fenêtre, quatre empreintes", .normalWear),
            Finding("r3", "Trace de coulure sur le mur nord, 30 cm sous le plafond", .disputes),
            Finding("r4", "Store à lamelles bloqué à mi-hauteur, cordon effiloché", .agrees),
            Finding("r4", "Plinthe décollée derrière la porte", .notStated),
            Finding("r5", "Interrupteur fendu à l’entrée", .agrees),
            Finding("r6", "Dalles de balcon déchaussées à l’angle sud-ouest", .existingAtEntry),
        ]
        p.defects = findings.enumerated().map { index, finding in
            Defect(id: "d\(index + 1)", roomId: finding.room, text: finding.text, chargedToTenant: index % 3 != 1, fixBy: index % 2 == 0 ? .landlord : .open,
                   costNote: index % 3 == 0 ? "Devis demandé, aucune reconnaissance de dette" : "",
                   reservation: index % 4 == 0 ? "Le locataire conteste la responsabilité" : "", tenantResponse: finding.response)
        }
        p.objects = [
            ObjectEntry(id: "o1", group: .appliance, label: "Lave-vaisselle encastré", roomId: "r1", note: "N° de série LV-2026-0142", inspected: true),
            ObjectEntry(id: "o2", group: .furniture, label: "Armoire murale du couloir", roomId: "r5", inspected: true),
        ]
        p.details.readings = [
            MeterReading(id: "m1", label: "Électricité", identifier: "CH1003-4821", value: "48214.7", unit: "kWh", date: "2026-10-21", time: "09:10"),
            MeterReading(id: "m2", label: "Eau froide", identifier: "EF-2210", value: "1210.3", unit: "m³", date: "2026-10-21", time: "09:12"),
            MeterReading(id: "m3", label: "Eau chaude", identifier: "EC-2211", value: "604.8", unit: "m³", date: "2026-10-21", time: "09:14"),
        ]
        p.keys = [KeyCount(.apartment, count: 3), KeyCount(.mailbox, count: 1)]
        p.keyTransfer = .allTransferred
        p.dossier = DossierCard.allCases
        p.remarks = "Mesure de l’annexe photographique : trente photographies réelles réparties entre les pièces, les constats, les objets et les compteurs."

        typealias Slot = (inout HandoverProtocol, PhotoEvidence) -> Void
        var slots: [Slot] = []
        for room in rooms {
            let slot: Slot = { p, e in p.details.roomPhotos[room.id] = (p.details.roomPhotos[room.id] ?? []) + [e] }
            slots.append(slot)
        }
        for index in findings.indices {
            let slot: Slot = { p, e in
                p.defects[index].photos.append(e.file)
                p.defects[index].photoEvidence.append(e)
            }
            for _ in 0..<(index < 8 ? 2 : 1) { slots.append(slot) }
        }
        for (index, count) in [2, 1].enumerated() {
            let slot: Slot = { p, e in
                p.objects[index].photos.append(e.file)
                p.objects[index].photoEvidence.append(e)
            }
            for _ in 0..<count { slots.append(slot) }
        }
        for index in 0..<3 {
            let slot: Slot = { p, e in p.details.readings[index].photos.append(e) }
            slots.append(slot)
        }
        for (index, source) in photos.enumerated() where index < slots.count {
            let name = String(format: "photo-%02d.jpg", index + 1)
            try FileManager.default.copyItem(at: source, to: photoDir.appendingPathComponent(name))
            let evidence = PhotoEvidence(name, sha256: try ProtocolIntegrity.fileHash(photoDir.appendingPathComponent(name)),
                                         capturedEpochMs: 1_792_566_600_000 + Int64(index) * 90_000, source: .camera)
            slots[index](&p, evidence)
        }

        try ink(inkDir.appendingPathComponent("tenant-record.png"), seed: 3)
        try ink(inkDir.appendingPathComponent("landlord-record.png"), seed: 11)
        p.signatures = [
            Signature(.tenant, name: "Jean Locataire", plane: .record, file: "tenant-record.png", contentRevision: 3),
            Signature(.landlord, name: "Claire Exemple", plane: .record, file: "landlord-record.png", contentRevision: 3),
        ]
        p.contentRevision = 3
        p.finalizedEpochMs = 1_792_575_600_000
        p.evidenceFingerprint = try ProtocolIntegrity.fingerprint(p, photoDir: photoDir, signatureDir: inkDir)
        try store.save(p)
        return p
    }

    /// A stroke of ink as a PNG, the shape the pad writes, so the signatures print.
    private func ink(_ file: URL, seed: CGFloat) throws {
        let width = 600, height = 200
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(CGColor(gray: 0.05, alpha: 1))
        context.setLineWidth(9)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: 40, y: 60))
        context.addCurve(to: CGPoint(x: 560, y: 110), control1: CGPoint(x: 150 + seed * 10, y: 190), control2: CGPoint(x: 400 - seed * 8, y: 10))
        context.strokePath()
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    // MARK: - Measuring

    private func resolve(_ path: String) throws -> URL {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : AppFiles.documents.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func size(_ file: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// The process's physical footprint, now and at its peak: the number the phone's memory limit
    /// is compared to.
    private static func footprintPeak() -> UInt64 { UInt64(vmInfo()?.ledger_phys_footprint_peak ?? 0) }
    private static func footprintNow() -> UInt64 { vmInfo()?.phys_footprint ?? 0 }

    private static func vmInfo() -> task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? info : nil
    }
}
