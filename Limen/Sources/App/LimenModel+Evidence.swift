import Foundation
import LimenKit

/// The evidence and the way out: photographs, ink, and the exported document.
extension LimenModel {
    // MARK: Photographs

    /// A photo the camera or picker delivered, preserved byte-for-byte beside the protocol and
    /// hashed at once, because the hash is what the fingerprint later covers. The owner is a
    /// defect or a supplied object; the file is named after it either way.
    nonisolated static func copyPhoto(into dir: URL, ownerId: String, existing: Int, source: URL, photoSource: PhotoSource) -> PhotoEvidence? {
        let ownerToken = EvidenceNames.isArchiveSafe(ownerId) ? String(ownerId.prefix(80)) : "e\(String(UInt32(truncatingIfNeeded: ownerId.hashValue), radix: 16))"
        let name = "\(ownerToken)-\(Int64(Date().timeIntervalSince1970 * 1000))-\(existing + 1).jpg"
        let target = dir.appendingPathComponent(name)
        do {
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
        try? FileManager.default.removeItem(at: source)
        // fileHash refuses an empty or unreadable file, and a copy onto a full card still
        // produces one. Dropping the photograph is the right answer.
        guard let hash = try? ProtocolIntegrity.fileHash(target) else {
            try? FileManager.default.removeItem(at: target)
            return nil
        }
        return PhotoEvidence(name, sha256: hash, capturedEpochMs: Int64(Date().timeIntervalSince1970 * 1000), source: photoSource)
    }

    /// The copy and the SHA-256 run off this thread: both walk the whole JPEG, and a gallery pick
    /// of a twelve-megapixel photograph froze the frame for as long as three passes take.
    func attachPhoto(_ defectId: String, source: URL, photoSource: PhotoSource = .unknown) {
        if contentLocked { return }
        guard let dir = photoDir() else { return }
        let had = working?.defects.first { $0.id == defectId }?.photos.count ?? 0
        Task {
            guard let evidence = await Task.detached(operation: { Self.copyPhoto(into: dir, ownerId: defectId, existing: had, source: source, photoSource: photoSource) }).value else { return }
            updateDefect(defectId) { defect in
                var d = defect
                d.photos.append(evidence.file)
                d.photoEvidence = d.photoEvidence.filter { $0.file != evidence.file } + [evidence]
                return d
            }
        }
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
        if contentLocked { return }
        guard let dir = photoDir() else { return }
        let had = working?.objects.first { $0.id == objectId }?.photos.count ?? 0
        Task {
            guard let evidence = await Task.detached(operation: { Self.copyPhoto(into: dir, ownerId: objectId, existing: had, source: source, photoSource: photoSource) }).value else { return }
            updateObject(objectId) { entry in
                var e = entry
                e.photos.append(evidence.file)
                e.photoEvidence = e.photoEvidence.filter { $0.file != evidence.file } + [evidence]
                return e
            }
        }
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

    func deleteSignatureFile(_ name: String) {
        guard EvidenceNames.isSafe(name), let dir = signatureDir() else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }

    /// Keeps the ink: the PNG is written beside the protocol and the record points at it.
    ///
    /// Staged and moved rather than written in place, and the write result is read. A write
    /// that failed part way left a truncated PNG with a length, which passed the evidence check
    /// and printed as an empty rule under a full signature caption.
    func keepSignature(_ role: Role, plane: Plane, png: Data) {
        if contentLocked { return }
        guard let dir = signatureDir(), !png.isEmpty else { return }
        let name = "\(role.rawValue.lowercased())-\(plane.rawValue.lowercased()).png"
        let target = dir.appendingPathComponent(name)
        let staged = dir.appendingPathComponent("\(name).part")
        do {
            try png.write(to: staged)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: staged, to: target)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            return
        }
        let partyName = working?.parties.first { $0.role == role }?.name ?? ""
        editSignatures { p in
            let reservation = (p.pendingRecordReservations[role] ?? p.signatures.first { $0.role == role && $0.plane == plane }?.reservation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var next = p
            next.signatures = p.signatures.filter { !($0.role == role && $0.plane == plane) } +
                [Signature(role, name: partyName, plane: plane, file: name, reservation: reservation, epochMs: Self.now(), contentRevision: p.contentRevision)]
            return next
        }
    }

    /// Refusal is an outcome the record keeps, not an error it recovers from.
    func refuseSignature(_ role: Role, plane: Plane) {
        if contentLocked { return }
        if let existing = working?.signatures.first(where: { $0.role == role && $0.plane == plane }), !existing.file.isBlank {
            deleteSignatureFile(existing.file)
        }
        let partyName = working?.parties.first { $0.role == role }?.name ?? ""
        editSignatures { p in
            let reservation = (p.pendingRecordReservations[role] ?? p.signatures.first { $0.role == role && $0.plane == plane }?.reservation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var next = p
            next.signatures = p.signatures.filter { !($0.role == role && $0.plane == plane) } +
                [Signature(role, name: partyName, plane: plane, refused: true, reservation: reservation, epochMs: Self.now(), contentRevision: p.contentRevision)]
            return next
        }
    }

    func clearSignature(_ role: Role, plane: Plane) {
        if contentLocked { return }
        let existing = working?.signatures.first { $0.role == role && $0.plane == plane }
        if let existing, !existing.file.isBlank { deleteSignatureFile(existing.file) }
        editSignatures { p in
            let reservation = existing?.reservation ?? ""
            var next = p
            next.signatures = p.signatures.filter { !($0.role == role && $0.plane == plane) }
            if !reservation.isBlank { next.pendingRecordReservations[role] = reservation }
            return next
        }
    }

    func setRecordReservation(_ role: Role, _ text: String) {
        // A reservation is printed in the shared record. Changing it after another person signed
        // must therefore move the revision and require that signature to be reviewed.
        edit { p in
            var next = p
            next.pendingRecordReservations[role] = text.isBlank ? nil : text
            return next
        }
    }

    // MARK: Export

    func selectPdfLang(_ l: Lang) { pdfLang = l }

    func exportPdf() {
        guard let p = working else { return }
        guard p.isFinalized() else {
            exportIssue = .notFinalized
            return
        }
        if exporting { return }
        exporting = true
        exportIssue = nil
        exported = nil
        let docLang = pdfLang ?? lang
        let store = store
        Task {
            let outcome: ExportOutcome = await Task.detached {
                let photos = store.photoDir(p.id)
                let ink = store.signatureDir(p.id)
                if !ProtocolIntegrity.matches(p, photoDir: photos, signatureDir: ink) { return .mismatch }
                do {
                    return .written(try PdfExport.export(p, Str(docLang), photoDir: photos, signatureDir: ink))
                } catch {
                    return .failed
                }
            }.value
            exporting = false
            // The export outlives the screen that started it. Everything it writes back is bound
            // to the record it was started for: closing the flow mid-export used to stamp the
            // moment onto whatever draft happened to be open when the writer finished.
            let stillOpen = working?.id == p.id
            switch outcome {
            case .mismatch:
                if stillOpen { exportIssue = .integrityMismatch }
            case .failed:
                if stillOpen { exportIssue = .failed }
            case .written(let file):
                var stamped = p
                stamped.exportedEpochMs = Self.now()
                try? store.save(stamped)
                if stillOpen {
                    exported = file
                    working = stamped
                }
                protocols = store.list()
            }
        }
    }

    enum ExportOutcome: Sendable {
        case written(ExportedFile)
        case mismatch
        case failed
    }

    func setDepositCompare(_ open: Bool) { showDepositCompare = open }

}
