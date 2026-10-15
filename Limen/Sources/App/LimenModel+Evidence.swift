import Foundation
import LimenKit

/// The evidence and the way out: photographs, ink, and the exported document.
extension LimenModel {
    // MARK: Photographs

    /// A photo the camera or picker delivered, preserved byte-for-byte beside the protocol and
    /// hashed at once, because the hash is what the fingerprint later covers. The owner is a
    /// defect or a supplied object; the file is named after it either way.
    nonisolated static func copyPhoto(into dir: URL, ownerId: String, existing: Int, source: URL, photoSource: PhotoSource) throws -> PhotoEvidence {
        let secured = source.startAccessingSecurityScopedResource()
        defer { if secured { source.stopAccessingSecurityScopedResource() } }
        let mime = try EvidenceValidation.validatePhoto(source)
        let suffix = ["image/jpeg": "jpg", "image/png": "png", "image/heic": "heic", "image/heif": "heif", "image/tiff": "tiff"][mime] ?? "image"
        let name = "photo-\(UUID().uuidString).\(suffix)"
        let target = dir.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: source, to: target)
            let hash = try ProtocolIntegrity.fileHash(target)
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            var evidence = PhotoEvidence(name, sha256: hash, capturedEpochMs: photoSource == .camera ? now : 0, source: photoSource)
            evidence.importedEpochMs = now
            return evidence
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
    }

    func attachPhoto(_ defectId: String, source: URL, photoSource: PhotoSource = .unknown) {
        intakePhoto(ownerId: defectId, source: source, photoSource: photoSource, kind: .defect)
    }

    func removePhoto(_ defectId: String, name: String) {
        if contentLocked { return }
        reversibleEdit(.photo, evidenceNames: [name]) { p in
            var next = p
            next.defects = p.defects.map { defect in
                guard defect.id == defectId else { return defect }
                var d = defect
                d.photos.removeAll { $0 == name }
                d.photoEvidence.removeAll { $0.file == name }
                return d
            }
            return next
        }
    }

    func attachObjectPhoto(_ objectId: String, source: URL, photoSource: PhotoSource = .unknown) {
        intakePhoto(ownerId: objectId, source: source, photoSource: photoSource, kind: .object)
    }

    func removeObjectPhoto(_ objectId: String, name: String) {
        if contentLocked { return }
        reversibleEdit(.photo, evidenceNames: [name]) { p in
            var next = p
            next.objects = p.objects.map { entry in
                guard entry.id == objectId else { return entry }
                var e = entry
                e.photos.removeAll { $0 == name }
                e.photoEvidence.removeAll { $0.file == name }
                return e
            }
            return next
        }
    }

    // MARK: Signatures

    // Evidence files are immutable once written. Clearing or replacing ink only removes its
    // reference; last-good records can still recover the original until the record is deleted.
    func deleteSignatureFile(_ name: String) {}

    func keepSignature(_ role: Role, plane: Plane, png: Data) {
        guard let party = working?.parties.first(where: { $0.role == role }) else { return }
        keepSignature(participantId: party.participantKey(), plane: plane, png: png)
    }

    func keepSignature(participantId: String, plane: Plane, png: Data) {
        guard !contentLocked, let p = working,
              let party = p.parties.first(where: { $0.participantKey() == participantId }) else { return }
        let target = store.signatureDir(p.id).appendingPathComponent("ink-\(UUID().uuidString).png")
        do {
            try png.write(to: target, options: .atomic)
            _ = try EvidenceValidation.validatePhoto(target)
            editSignatures { current in
                var next = current
                var signature = Signature(party.role, name: party.signerName(), plane: plane, file: target.lastPathComponent,
                                          reservation: current.reservationFor(party: party), epochMs: Self.now(), contentRevision: current.contentRevision)
                signature.participantId = participantId
                next.signatures.removeAll { Self.belongs($0, to: party, plane: plane) }
                next.signatures.append(signature)
                return next
            }
        } catch {
            try? FileManager.default.removeItem(at: target)
            evidenceError = error.localizedDescription
        }
    }

    nonisolated static func belongs(_ signature: Signature, to party: Party, plane: Plane) -> Bool {
        signature.plane == plane && (signature.participantId.isEmpty ? party.id.isEmpty && signature.role == party.role : signature.participantId == party.participantKey())
    }

    func refuseSignature(_ role: Role, plane: Plane) {
        guard let party = working?.parties.first(where: { $0.role == role }) else { return }
        outcomeSignature(participantId: party.participantKey(), outcome: "refused", plane: plane)
    }

    func outcomeSignature(participantId: String, outcome: String, plane: Plane = .record) {
        guard ["refused", "absent", "unable"].contains(outcome), !contentLocked,
              let party = working?.parties.first(where: { $0.participantKey() == participantId }) else { return }
        editSignatures { p in
            var next = p
            var signature = Signature(party.role, name: party.signerName(), plane: plane, refused: outcome == "refused",
                                      reservation: p.reservationFor(party: party), epochMs: Self.now(), contentRevision: p.contentRevision)
            signature.participantId = participantId
            signature.outcome = outcome == "refused" ? "" : outcome
            next.signatures.removeAll { Self.belongs($0, to: party, plane: plane) }
            next.signatures.append(signature)
            return next
        }
    }

    func clearSignature(_ role: Role, plane: Plane) {
        guard let party = working?.parties.first(where: { $0.role == role }) else { return }
        clearSignature(participantId: party.participantKey(), plane: plane)
    }

    func clearSignature(participantId: String, plane: Plane) {
        guard let party = working?.parties.first(where: { $0.participantKey() == participantId }) else { return }
        editSignatures { p in
            var next = p
            next.details.reservations[participantId] = p.reservationFor(party: party)
            next.signatures.removeAll { Self.belongs($0, to: party, plane: plane) }
            return next
        }
    }

    func setRecordReservation(_ role: Role, _ text: String) {
        guard let party = working?.parties.first(where: { $0.role == role }) else { return }
        setRecordReservation(participantId: party.participantKey(), text)
    }

    func setRecordReservation(participantId: String, _ text: String) {
        edit { p in
            var next = p
            next.details.reservations[participantId] = text
            return next
        }
    }

    // MARK: Export

    func selectPdfLang(_ l: Lang) { pdfLang = l }

    func exportPdf() {
        guard let p = working else { return }
        guard p.isFinalized() else { exportIssue = .notFinalized; return }
        guard !exporting, flush(), let snapshot = working else { return }
        exporting = true
        exportIssue = nil
        let docLang = pdfLang ?? lang
        let store = store
        let renderer = exportRenderer
        let retainedDirectory = store.root.appendingPathComponent("exports").appendingPathComponent(snapshot.id)
        let publicDirectory = Exports.folder
        let existingRetained = Set((try? FileManager.default.contentsOfDirectory(atPath: retainedDirectory.path)) ?? [])
        let existingPublic = Set((try? FileManager.default.contentsOfDirectory(atPath: publicDirectory.path)) ?? [])
        exportTask = Task {
            let result: Result<ExportCopy, Error>
            do { result = .success(try await renderer(snapshot, Str(docLang), store)) } catch { result = .failure(error) }
            exporting = false
            switch result {
            case .success(let copy):
                // Merge only metadata into the latest state. A delivery can change while the
                // renderer works; the copy keeps the revision it actually rendered.
                let saved = store.load(snapshot.id)
                let current = working?.id == snapshot.id ? working : saved
                guard let saved, saved.isFinalized(), saved.evidenceFingerprint == snapshot.evidenceFingerprint,
                      var latest = current, latest.isFinalized(), latest.evidenceFingerprint == snapshot.evidenceFingerprint else {
                    let protected = Set((snapshot.exportHistory + (saved?.exportHistory ?? []) + (current?.exportHistory ?? [])).map(\.name))
                    Self.discardExport(copy, directory: retainedDirectory, existing: existingRetained.union(protected))
                    Self.discardExport(copy, directory: publicDirectory, existing: existingPublic.union(protected))
                    return
                }
                latest.exportedEpochMs = copy.epochMs
                latest.exportHistory.append(copy)
                latest.saveSequence += 1
                if working?.id == snapshot.id { working = latest }
                do {
                    try store.save(latest)
                    if working?.id == snapshot.id { restoreExport(latest); saveError = nil }
                } catch {
                    if working?.id == snapshot.id { saveError = str.saveFailed + " (\(error.localizedDescription))" }
                }
                refreshLibrary()
            case .failure(let error):
                if working?.id == snapshot.id {
                    exportIssue = .failed
                    evidenceError = error.localizedDescription
                }
            }
        }
    }

    /// A completed render can outlive its record. Remove only its new pair, never an older copy,
    /// an unrelated file, or anything reached through the descriptive cross-device URI fields.
    nonisolated private static func discardExport(_ copy: ExportCopy, directory: URL, existing: Set<String>) {
        guard EvidenceNames.isArchiveSafe(copy.name), !existing.contains(copy.name), !copy.sha256.isEmpty else { return }
        let pdf = directory.appendingPathComponent(copy.name)
        guard let hash = try? ProtocolIntegrity.fileHash(pdf), hash == copy.sha256 else { return }
        try? FileManager.default.removeItem(at: pdf)
        let html = pdf.deletingPathExtension().appendingPathExtension("html")
        if !existing.contains(html.lastPathComponent) { try? FileManager.default.removeItem(at: html) }
    }

    func openExport(_ copy: ExportCopy) {
        guard var record = working else { return }
        record.exportHistory = [copy]
        restoreExport(record)
    }

    func restoreExport(_ record: HandoverProtocol) {
        exported = nil
        accessibleExport = nil
        for copy in record.exportHistory.reversed() {
            let pdf = store.root.appendingPathComponent("exports").appendingPathComponent(record.id).appendingPathComponent(copy.name)
            guard EvidenceNames.isSafe(copy.name), FileManager.default.fileExists(atPath: pdf.path),
                  let hash = try? ProtocolIntegrity.fileHash(pdf), !copy.sha256.isEmpty, hash == copy.sha256 else { continue }
            exported = ExportedFile(url: pdf, displayName: copy.name, bytes: copy.bytes)
            let html = pdf.deletingPathExtension().appendingPathExtension("html")
            if let size = try? html.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                accessibleExport = ExportedFile(url: html, displayName: html.lastPathComponent, bytes: Int64(size))
            }
            break
        }
    }

    func setDepositCompare(_ open: Bool) { showDepositCompare = open }

}
