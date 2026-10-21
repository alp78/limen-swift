import Foundation
import LimenKit
import LocalAuthentication
import UIKit

extension LimenModel {
    func refreshLibrary() {
        libraryGeneration += 1
        let generation = libraryGeneration
        libraryLoading = true
        let store = store
        Task {
            let catalogue = await Task.detached { store.catalogue() }.value
            guard libraryGeneration == generation else { return }
            protocols = catalogue.records
            unreadableRecords = catalogue.unreadable
            libraryLoading = false
        }
    }

    func recoverRecord(_ id: String) {
        guard working?.id != id else { return }
        do {
            _ = try store.recover(id)
            refreshLibrary()
        } catch { evidenceError = error.localizedDescription }
    }

    func setLibraryProtectionEnabled(_ enabled: Bool) {
        guard !libraryAuthenticationBusy else { return }
        guard enabled else {
            libraryProtectionEnabled = false
            prefs.set(false, forKey: "libraryProtectionEnabled")
            libraryUnlocked = false
            return
        }
        // Verify credentials before persisting the preference: a device with no passcode
        // must never enter a gate that its owner cannot unlock or disable.
        authenticateLibrary(enabling: true)
    }

    func requestHomePage(_ page: HomePage) {
        guard libraryProtectionEnabled, !libraryUnlocked, page == .sessions || page == .dataPrivacy else {
            homePage = page
            return
        }
        authenticateLibrary(destination: page)
    }

    private func authenticateLibrary(enabling: Bool = false, destination: HomePage? = nil) {
        guard !libraryAuthenticationBusy else { return }
        let context = LAContext()
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            evidenceError = availabilityError?.localizedDescription ?? str.openFileFailed
            return
        }
        libraryAuthenticationBusy = true
        Task {
            defer { libraryAuthenticationBusy = false }
            do {
                guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: str.protocols),
                      UIApplication.shared.applicationState == .active else { return }
                if enabling {
                    libraryProtectionEnabled = true
                    prefs.set(true, forKey: "libraryProtectionEnabled")
                }
                libraryUnlocked = true
                if let destination { homePage = destination }
            } catch { evidenceError = error.localizedDescription }
        }
    }

    func saveReusableIdentity(_ identity: SessionIdentity) {
        reusableIdentity = identity
        var container = HandoverProtocol(id: "profile", kind: .entry, createdEpochMs: 0)
        container.sessionIdentity = identity
        prefs.set(Data(Store.fileText(container).utf8), forKey: "reusableIdentity")
    }

    func rememberValidInput(key: String, value: String) {
        guard let id = working?.id else { return }
        prefs.set(value, forKey: "validInput.\(id).\(key)")
    }

    func lastValidInput(key: String) -> String? {
        guard let id = working?.id else { return nil }
        return prefs.string(forKey: "validInput.\(id).\(key)")
    }

    func confirmMaterialEdit() {
        guard let current = working, let next = pendingEdit,
              current.id == next.id, current.contentRevision == pendingEditRevision, !contentLocked else {
            cancelMaterialEdit()
            return
        }
        cancelMaterialEdit()
        applyContentEdit(next, from: current)
    }

    func cancelMaterialEdit() {
        pendingEdit = nil
        pendingEditNames = []
        pendingEditRevision = nil
    }

    func addParticipant(role: Role) {
        edit { p in
            var next = p
            var party = Party(role)
            party.id = UUID().uuidString
            next.parties.append(party)
            return next
        }
    }

    func removeParticipant(id: String) {
        edit { p in
            var next = p
            next.parties.removeAll { $0.participantKey() == id }
            next.signatures.removeAll { $0.participantId == id }
            next.details.reservations[id] = nil
            return next
        }
    }

    func updateParticipant(id: String, _ transform: (Party) -> Party) {
        edit { p in
            var next = p
            next.parties = p.parties.map { $0.participantKey() == id ? transform($0) : $0 }
            return next
        }
    }

    func requiredRecordParticipants(_ p: HandoverProtocol? = nil) -> [Party] {
        guard let p = p ?? working else { return [] }
        return CompletionRules.requiredRecordParticipants(p, fallbackRole: myRole)
    }

    func moveRoom(id: String, offset: Int) {
        edit { p in
            guard let index = p.rooms.firstIndex(where: { $0.id == id }),
                  p.rooms.indices.contains(index + offset) else { return p }
            var next = p
            next.rooms.swapAt(index, index + offset)
            return next
        }
    }

    func nextRoom() {
        guard let p = working, let index = p.rooms.firstIndex(where: { $0.id == openRoomId }) else { return }
        openRoomId = p.rooms.indices.contains(index + 1) ? p.rooms[index + 1].id : nil
    }

    func previewDocument(_ record: HandoverProtocol? = nil) {
        guard let p = record ?? working, !previewBusy else { return }
        previewBusy = true
        previewError = nil
        documentPreview = nil
        documentPreviewHTML = nil
        previewRecordId = nil
        previewRevision = nil
        let store = store
        let documentLang = pdfLang ?? lang
        let renderer = previewRenderer
        previewTask = Task {
            let result: Result<(pdf: ExportedFile, html: ExportedFile), Error>
            do {
                let document = try await renderer(p, Str(documentLang), store)
                // The renderer already wrote both into the scratch folder; they are moved under
                // the preview's own name rather than copied, since a record of thirty
                // photographs is tens of megabytes.
                let name = "preview-\(UUID().uuidString)"
                let pdf = try Exports.write(name: "\(name).pdf", in: AppFiles.scratch) { try FileManager.default.moveItem(at: document.pdf, to: $0) }
                let html = try Exports.write(name: "\(name).html", in: AppFiles.scratch) { try FileManager.default.moveItem(at: document.html, to: $0) }
                result = .success((pdf, html))
            } catch { result = .failure(error) }
            previewBusy = false
            // Entry previews intentionally belong to the baseline, but still cannot replace a
            // preview in a different handover after the renderer suspends.
            guard working?.id == p.id || entryBaseline?.id == p.id else { return }
            switch result {
            case .success(let files):
                guard (working?.id == p.id && working?.contentRevision == p.contentRevision) || entryBaseline?.id == p.id else { return }
                documentPreview = files.pdf
                documentPreviewHTML = files.html
                previewRecordId = p.id
                previewRevision = p.contentRevision
            case .failure(let error): previewError = error.localizedDescription
            }
        }
    }

    func confirmReview() {
        guard let current = working, documentPreview != nil, documentPreviewHTML != nil,
              previewRecordId == current.id, previewRevision == current.contentRevision else { return }
        editSignatures { p in
            var next = p
            next.details.reviewRevision = p.contentRevision
            return next
        }
    }
}
