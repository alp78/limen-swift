import Foundation
import LimenKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

extension LimenModel {
    enum PhotoOwner: Sendable { case defect, object, room, meter }

    /// The gallery half of an intake: the picked item is loaded here, not in the picker's view,
    /// whose task ended the moment the editor closed and took the picked photograph with it. It
    /// counts as busy like the stages after it, so finalizing cannot slip in while a large or
    /// cloud-backed pick is still arriving, and `owner` is held in `photosInFlight` like the
    /// attach that follows. `onFile` runs on the main actor straight after both drop, so the
    /// attach that follows raises them again unseen.
    @discardableResult
    func loadPicked(_ item: PhotosPickerItem, owner: String, kind: PhotoOwner, onFile: @escaping (URL) -> Void) -> Task<Void, Never>? {
        guard !contentLocked, let p = working else { return nil }
        evidenceBusy += 1
        if kind == .defect { photosInFlight.append(owner) }
        return Task {
            let result: Result<URL?, Error>
            do { result = .success(try await item.loadTransferable(type: ImportedPhoto.self)?.url) } catch { result = .failure(error) }
            evidenceBusy -= 1
            if kind == .defect, let i = photosInFlight.firstIndex(of: owner) { photosInFlight.remove(at: i) }
            // Handed on only while the record is still the one the pick was made on: the attach
            // that follows reads the open record when it runs, and by now the person may have left
            // it for another, which would take the file or drop it without a word.
            switch result {
            case .success(let url?) where working?.id == p.id && !contentLocked:
                onFile(url)
            case .success(let url):
                if let url { try? FileManager.default.removeItem(at: url) }
                if working?.id == p.id, contentLocked { evidenceError = str.evidenceAfterFinalized }
            case .failure:
                photoFailed(recordId: p.id, defectId: kind == .defect ? owner : "")
            }
        }
    }

    /// A photograph that did not arrive. Said on the record it was for; once the person has moved
    /// on it is a passing notice, because `evidenceError` belongs to whichever record is open and
    /// would print on that one. A finding opened for the photograph and closed since is left
    /// empty by the failure, so it goes where `closeDefect` would have sent it.
    func photoFailed(recordId: String, defectId: String = "") {
        guard working?.id == recordId else {
            show(str.photoNotAdded)
            return
        }
        evidenceError = str.photoNotAdded
        if !defectId.isEmpty, editingDefectId != defectId { discardEmptyShell(defectId) }
    }

    @discardableResult
    func intakePhoto(ownerId: String, source: URL, photoSource: PhotoSource, kind: PhotoOwner) -> Task<Void, Never>? {
        guard !contentLocked, let p = working else { return nil }
        let dir = store.photoDir(p.id)
        evidenceBusy += 1
        if kind == .defect { photosInFlight.append(ownerId) }
        return Task {
            let result = await Task.detached {
                Result { try Self.copyPhoto(into: dir, ownerId: ownerId, existing: 0, source: source, photoSource: photoSource) }
            }.value
            evidenceBusy -= 1
            if kind == .defect, let i = photosInFlight.firstIndex(of: ownerId) { photosInFlight.remove(at: i) }
            // Only the operation's own private capture is cleaned up, never another picker's.
            if source.deletingLastPathComponent().standardizedFileURL == AppFiles.captures.standardizedFileURL {
                try? FileManager.default.removeItem(at: source)
            }
            switch result {
            case .failure:
                photoFailed(recordId: p.id, defectId: kind == .defect ? ownerId : "")
            case .success(let evidence):
                guard let current = working, current.id == p.id, !contentLocked,
                      ownerExists(ownerId, kind: kind, in: current) else {
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent(evidence.file))
                    // The record was finalized before the file was stored: said, not swallowed.
                    if working?.id == p.id, contentLocked { evidenceError = str.evidenceAfterFinalized }
                    return
                }
                edit { record in
                    var next = record
                    switch kind {
                    case .defect:
                        if let i = next.defects.firstIndex(where: { $0.id == ownerId }) {
                            next.defects[i].photos.append(evidence.file)
                            next.defects[i].photoEvidence.append(evidence)
                        }
                    case .object:
                        if let i = next.objects.firstIndex(where: { $0.id == ownerId }) {
                            next.objects[i].photos.append(evidence.file)
                            next.objects[i].photoEvidence.append(evidence)
                        }
                    case .room: next.details.roomPhotos[ownerId] = (next.details.roomPhotos[ownerId] ?? []) + [evidence]
                    case .meter:
                        if let i = next.details.readings.firstIndex(where: { $0.id == ownerId }) { next.details.readings[i].photos.append(evidence) }
                    }
                    return next
                }
            }
        }
    }

    func ownerExists(_ id: String, kind: PhotoOwner, in p: HandoverProtocol) -> Bool {
        switch kind {
        case .defect: return p.defects.contains { $0.id == id }
        case .object: return p.objects.contains { $0.id == id }
        case .room: return p.rooms.contains { $0.id == id }
        case .meter: return p.details.readings.contains { $0.id == id }
        }
    }

    func attachRoomPhoto(_ id: String, source: URL, photoSource: PhotoSource = .unknown) {
        intakePhoto(ownerId: id, source: source, photoSource: photoSource, kind: .room)
    }

    func attachMeterPhoto(_ id: String, source: URL, photoSource: PhotoSource = .unknown) {
        intakePhoto(ownerId: id, source: source, photoSource: photoSource, kind: .meter)
    }

    func removeRoomPhoto(_ id: String, name: String) {
        reversibleEdit(.photo, evidenceNames: [name]) { p in
            var next = p
            next.details.roomPhotos[id] = (next.details.roomPhotos[id] ?? []).filter { $0.file != name }
            return next
        }
    }

    func removeMeterPhoto(_ id: String, name: String) {
        reversibleEdit(.photo, evidenceNames: [name]) { p in
            var next = p
            if let index = next.details.readings.firstIndex(where: { $0.id == id }) { next.details.readings[index].photos.removeAll { $0.file == name } }
            return next
        }
    }

    @discardableResult
    func importDocument(source: URL, kind: DocumentKind, title: String = "") -> Task<Void, Never>? {
        guard let p = working, !contentLocked else { return nil }
        let directory = store.photoDir(p.id)
        evidenceBusy += 1
        return Task {
            defer { evidenceBusy -= 1 }
            let result = await Task.detached {
                Result {
                    let secured = source.startAccessingSecurityScopedResource()
                    defer { if secured { source.stopAccessingSecurityScopedResource() } }
                    let mime = try EvidenceValidation.validateDocument(source)
                    let suffix = UTType(mimeType: mime)?.preferredFilenameExtension ?? "document"
                    let name = "document-\(UUID().uuidString).\(suffix)"
                    let target = directory.appendingPathComponent(name)
                    do {
                        try FileManager.default.copyItem(at: source, to: target)
                        let hash = try ProtocolIntegrity.fileHash(target)
                        let size = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        return SupportingDocument(id: UUID().uuidString, kind: kind, title: title.ifBlank(source.deletingPathExtension().lastPathComponent),
                                                  file: name, mime: mime, sha256: hash, bytes: Int64(size),
                                                  importedEpochMs: Int64(Date().timeIntervalSince1970 * 1000))
                    } catch {
                        try? FileManager.default.removeItem(at: target)
                        throw error
                    }
                }
            }.value
            switch result {
            case .success(let document):
                guard working?.id == p.id, !contentLocked else {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent(document.file))
                    if working?.id == p.id, contentLocked { evidenceError = str.evidenceAfterFinalized }
                    return
                }
                edit { record in
                    var next = record
                    next.details.attachments.append(document)
                    return next
                }
            case .failure:
                if working?.id == p.id { evidenceError = str.documentNotAdded }
            }
        }
    }

    func documentURL(_ document: SupportingDocument) -> URL? {
        guard EvidenceNames.isSafe(document.file), let dir = photoDir() else { return nil }
        return dir.appendingPathComponent(document.file)
    }

    func recordDelivery(participantId: String, method: DeliveryMethod, note: String = "") {
        guard let p = working, p.isFinalized(), p.isExported(),
              let party = p.parties.first(where: { $0.participantKey() == participantId }),
              method != .other || !note.isBlank else { return }
        editMetadata { p in
            var next = p
            var receipt = DeliveryReceipt(party.role, epochMs: Self.now(), method: method, note: note)
            receipt.participantId = participantId
            next.deliveryReceipts.removeAll { $0.participantId == participantId || ($0.participantId.isBlank && party.id.isBlank && $0.role == party.role) }
            next.deliveryReceipts.append(receipt)
            next.deliveryRevision += 1
            next.deliveryMetadataEpochMs = Self.now()
            return next
        }
    }

    func clearDelivery(participantId: String) {
        guard let p = working, p.isFinalized(), let party = p.parties.first(where: { $0.participantKey() == participantId }) else { return }
        editMetadata { p in
            var next = p
            next.deliveryReceipts.removeAll { $0.participantId == participantId || ($0.participantId.isBlank && party.id.isBlank && $0.role == party.role) }
            next.deliveryRevision += 1
            next.deliveryMetadataEpochMs = Self.now()
            return next
        }
    }
}
