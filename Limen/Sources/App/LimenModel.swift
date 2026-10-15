import Foundation
import LimenKit
import Observation
import UIKit

let keyDark = "darkTheme"
let keyLang = "lang"
let keyOpen = "openProtocol"
let keyStep = "openStep"
let keyRoom = "openRoom"
let keyDefect = "openDefect"
let keyRole = "myRole"
let keyName = "profileName"
let keyCompany = "profileCompany"
let keyControllerOrganisation = "controllerOrganisation"
let keyControllerContact = "controllerContact"
let keyControllerStreet = "controllerStreet"
let keyControllerPostal = "controllerPostalCode"
let keyControllerCity = "controllerCity"
let keyControllerEmail = "controllerEmail"
let keyControllerPhone = "controllerPhone"

/// How long the draft waits before it reaches the disk. Long enough that a burst of typing
/// writes once, short enough that it is over before a thumb reaches the next control.
private let saveDelay: Duration = .milliseconds(400)

/// How far back the flow can retrace. Deep enough for any real walk, bounded so it cannot grow.
private let maxTrail = 12

enum HomePage: String {
    case landing, newSession, sessions, dataPrivacy
}

struct UndoNotice: Equatable {
    let token: UInt64
    let kind: UndoKind
}

struct PendingUndo {
    let token: UInt64
    let before: HandoverProtocol
    let afterRevision: Int64
    let files: [URL]
}

/// The app's state: who holds the phone, the case, and the record being walked.
///
/// Every piece of state it publishes is observed, so a view that reads it is repainted when it
/// moves. Every edit funnels through `edit`, which is the one place the finalized lock, the
/// revision bump and the debounced save are enforced. The state is written by the model's own
/// methods, here and in the sibling extension files, and by nothing else: the setters are open
/// only because Swift has no access level that spans three files and stops at a view.
@MainActor
@Observable
final class LimenModel {
    let prefs: UserDefaults
    let store: Store

    // MARK: Who holds this phone

    /// The side of the threshold this install belongs to; nil until the first-run answer.
    var myRole: Role?
    var profileName: String
    /// The agency's firm name when this phone belongs to a Verwaltung; blank for private actors.
    var profileCompany: String
    var controllerIdentity: ControllerIdentity

    var darkTheme: Bool
    /// The language the instrument speaks; first run follows the system, then it is a choice.
    var lang: Lang
    var str: Str { Str(lang) }

    /// The home page and the entry an exit is being seeded from. Held here rather than in the
    /// home view, which is swapped out whole whenever a record opens: remembered there, the
    /// page was forgotten on every return from a handover.
    var homePage: HomePage = .landing
    var entryToSeedId: String?

    // MARK: The case

    var protocols: [HandoverProtocol]
    var libraryLoading = false
    var unreadableRecords: [Store.UnreadableRecord] = []
    var libraryGeneration = 0
    var addressLookupEnabled = false
    var libraryProtectionEnabled = false
    var libraryUnlocked = false
    var libraryAuthenticationBusy = false
    var archiveSelection: Set<String> = []
    var reusableIdentity = SessionIdentity()
    var archiveBusy = false
    var archiveExported: ExportedFile?
    /// Whether the last export carried a password, so the screen can say when it did not.
    var archiveProtected = true
    var archiveImported: ArchiveImportResult?
    var archiveFailed = false

    // MARK: The flow

    /// The protocol being walked, or nil when the case is showing. Saved on every edit.
    var saveError: String?
    var evidenceError: String?
    var pendingEdit: HandoverProtocol?
    var pendingEditRevision: Int64?
    var pendingEditNames: [String] = []
    var documentPreview: ExportedFile?
    var documentPreviewHTML: ExportedFile?
    var previewRecordId: String?
    var previewRevision: Int64?
    var previewBusy = false
    var previewTask: Task<Void, Never>?
    var previewRenderer: @Sendable (HandoverProtocol, Str, Store) async throws -> PdfExport.Document = { record, strings, store in
        try await Task.detached { try PdfExport.document(record, strings, photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id)) }.value
    }
    var previewError: String?
    var accessibleExport: ExportedFile?
    var working: HandoverProtocol?
    /// The entry record shown beside an exit inspection, never copied into the mutable exit.
    var entryBaseline: HandoverProtocol?
    var flowStep: FlowStep = .hub
    var dossierTarget: String?
    /// The steps walked to get here, so back retraces the route rather than guessing it.
    var flowTrail: [FlowStep] = []
    /// The room being inspected, or nil while the grid of rooms is showing. Held by id rather
    /// than by index so removing a room cannot silently open a different one.
    var openRoomId: String?
    /// The defect being edited, or nil. A new defect is created on opening the editor.
    var editingDefectId: String?
    var finalizing = false
    var amendmentInProgress = false
    /// A disk that filled while the photographs were being copied, said rather than swallowed.
    var amendmentError = false
    var finalizationIssues: [FinalizationIssue] = []
    var finalizationError = false
    var undoNotice: UndoNotice?
    /// A passing message, where Android showed a toast.
    var notice: String?
    var showDepositCompare = false

    var exporting = false
    var exportTask: Task<Void, Never>?
    var exportRenderer: @Sendable (HandoverProtocol, Str, Store) async throws -> ExportCopy = { record, strings, store in
        try await Task.detached { try PdfExport.exportRetained(record, strings, store: store) }.value
    }
    var exported: ExportedFile?
    var exportIssue: ExportIssue?
    /// The document's language, chosen at export and free of the UI language.
    var pdfLang: Lang?

    /// The record as it stood before the defect editor wrote its shell, keyed by that shell's id.
    var defectShell: (String, HandoverProtocol)?
    var pendingUndo: PendingUndo?
    var undoTask: Task<Void, Never>?
    var saveTask: Task<Void, Never>?
    var noticeTask: Task<Void, Never>?

    init(prefs: UserDefaults = .standard, root: URL = AppFiles.support) {
        self.prefs = prefs
        store = Store(root: root)
        myRole = prefs.string(forKey: keyRole).flatMap(Role.init(rawValue:))
        profileName = prefs.string(forKey: keyName) ?? ""
        profileCompany = prefs.string(forKey: keyCompany) ?? ""
        var controller = ControllerIdentity()
        controller.organisation = prefs.string(forKey: keyControllerOrganisation) ?? ""
        controller.contactName = prefs.string(forKey: keyControllerContact) ?? ""
        controller.street = prefs.string(forKey: keyControllerStreet) ?? ""
        controller.postalCode = prefs.string(forKey: keyControllerPostal) ?? ""
        controller.city = prefs.string(forKey: keyControllerCity) ?? ""
        controller.email = prefs.string(forKey: keyControllerEmail) ?? ""
        controller.phone = prefs.string(forKey: keyControllerPhone) ?? ""
        controllerIdentity = controller
        darkTheme = prefs.bool(forKey: keyDark)
        lang = Lang.from(prefs.string(forKey: keyLang))
        protocols = []
        addressLookupEnabled = prefs.bool(forKey: "addressLookupEnabled")
        libraryProtectionEnabled = prefs.bool(forKey: "libraryProtectionEnabled")
        if let bytes = prefs.data(forKey: "reusableIdentity"), let p = try? ProtocolJSON.decode(bytes) { reusableIdentity = p.sessionIdentity }
        refreshLibrary()
        // Reopens whatever record was on screen when the process last ended.
        if let openId = prefs.string(forKey: keyOpen), !openId.isBlank {
            if let recovered = store.load(openId) {
                setActiveProtocol(recovered)
                flowStep = prefs.string(forKey: keyStep).flatMap(FlowStep.init(rawValue:)) ?? .hub
                // Both are checked against the record rather than trusted: a room or a finding
                // can have been removed by an amendment, or by another restore, since the process died.
                openRoomId = prefs.string(forKey: keyRoom).flatMap { id in recovered.rooms.contains { $0.id == id } ? id : nil }
                editingDefectId = prefs.string(forKey: keyDefect).flatMap { id in recovered.defects.contains { $0.id == id } ? id : nil }
            } else {
                prefs.removeObject(forKey: keyOpen)
            }
        }
    }

    func updateController(_ identity: ControllerIdentity) {
        controllerIdentity = identity
        prefs.set(identity.organisation, forKey: keyControllerOrganisation)
        prefs.set(identity.contactName, forKey: keyControllerContact)
        prefs.set(identity.street, forKey: keyControllerStreet)
        prefs.set(identity.postalCode, forKey: keyControllerPostal)
        prefs.set(identity.city, forKey: keyControllerCity)
        prefs.set(identity.email, forKey: keyControllerEmail)
        prefs.set(identity.phone, forKey: keyControllerPhone)
    }

    func chooseRole(_ role: Role, name: String, company: String = "") {
        myRole = role
        profileName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profileCompany = company.trimmingCharacters(in: .whitespacesAndNewlines)
        prefs.set(role.rawValue, forKey: keyRole)
        prefs.set(profileName, forKey: keyName)
        prefs.set(profileCompany, forKey: keyCompany)
    }

    /// Forgets who holds the phone: back to the first question, nothing else touched.
    func clearProfile() {
        myRole = nil
        profileName = ""
        profileCompany = ""
        prefs.removeObject(forKey: keyRole)
        prefs.removeObject(forKey: keyName)
        prefs.removeObject(forKey: keyCompany)
    }

    func selectLang(_ l: Lang) {
        lang = l
        prefs.set(l.rawValue, forKey: keyLang)
    }

    func toggleTheme() {
        darkTheme.toggle()
        prefs.set(darkTheme, forKey: keyDark)
    }

    func show(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled && !UIAccessibility.isVoiceOverRunning { notice = nil }
        }
    }

    // MARK: Archive

    func exportArchive(password: String) {
        if archiveBusy { return }
        guard flush() else { return }
        archiveProtected = !password.isEmpty
        archiveBusy = true
        archiveExported = nil
        archiveImported = nil
        archiveFailed = false
        let store = store
        let selected = archiveSelection.isEmpty ? nil : archiveSelection
        let name = "Limen-backup-\(Exports.stamp()).limen"
        Task {
            let result: Result<ExportedFile, Error> = await Task.detached {
                Result { try Exports.write(name: name) { url in try store.exportArchive(password: password, to: url, protocolIds: selected) } }
            }.value
            archiveBusy = false
            switch result {
            case .success(let file): archiveExported = file
            case .failure: archiveFailed = true
            }
        }
    }

    func importArchive(_ url: URL, password: String) {
        if archiveBusy { return }
        guard flush() else { return }
        archiveBusy = true
        archiveExported = nil
        archiveImported = nil
        archiveFailed = false
        let store = store
        Task {
            let result: Result<ArchiveImportResult, Error> = await Task.detached {
                // The picker's file lives outside the sandbox; it is readable only inside this scope.
                let secured = url.startAccessingSecurityScopedResource()
                defer { if secured { url.stopAccessingSecurityScopedResource() } }
                return Result { try store.importArchive(password: password, from: url) }
            }.value
            archiveBusy = false
            switch result {
            case .success(let imported):
                archiveImported = imported
                refreshLibrary()
            case .failure:
                archiveFailed = true
            }
        }
    }

    // MARK: The flow

    func photoDir() -> URL? { working.map { store.photoDir($0.id) } }
    func signatureDir() -> URL? { working.map { store.signatureDir($0.id) } }

    func setActiveProtocol(_ p: HandoverProtocol?) {
        commitUndo()
        // Everything below belongs to the record being left, not to the one arriving. An
        // amendment switches protocols without an intervening close, and inherited these: the
        // parent's exported PDF was then offered on the amendment's own export step.
        exported = nil
        accessibleExport = nil
        documentPreview = nil
        documentPreviewHTML = nil
        pendingEdit = nil
        pendingEditNames = []
        exportIssue = nil
        pdfLang = nil
        defectShell = nil
        flowTrail = []
        working = p
        if let p { restoreExport(p) }
        entryBaseline = nil
        if let p, p.kind == .exit, !p.seedId.isBlank, let entry = store.load(p.seedId), entry.isFinalized() {
            entryBaseline = entry
        }
    }

    /// Every edit funnels through here. The draft in the hand changes at once; the draft on disk
    /// follows a moment later, off this thread. Nothing is risked: `flush` runs on every edge
    /// that can end the process or read the file back.
    func edit(_ transform: (HandoverProtocol) -> HandoverProtocol) {
        commitUndo()
        guard let p = working, !p.isFinalized(), !finalizing else { return }
        // Two owned intake operations can finish while consent is open. Accumulate their
        // proposed changes instead of replacing one with another snapshot of the same draft.
        let base = pendingEdit?.id == p.id && pendingEditRevision == p.contentRevision ? pendingEdit ?? p : p
        let edited = transform(base)
        if edited == base { return }
        let affected = p.signatures.filter { p.isCurrent($0) && !$0.file.isBlank }.map(\.name).filter { !$0.isBlank }.distinct()
        if !affected.isEmpty {
            pendingEdit = edited
            pendingEditRevision = p.contentRevision
            pendingEditNames = affected
            return
        }
        applyContentEdit(edited, from: p)
    }

    func applyContentEdit(_ edited: HandoverProtocol, from p: HandoverProtocol) {
        var next = edited
        // A background flush may have saved while material-edit consent was open.
        next.saveSequence = p.saveSequence
        next.contentRevision = p.contentRevision + 1
        next.exportedEpochMs = 0
        documentPreview = nil
        documentPreviewHTML = nil
        previewRevision = nil
        previewRecordId = nil
        next.details.reviewRevision = -1
        next.details.legalSnapshot = nil
        for requirement in p.invalidatedLegalRequirements(next: next) {
            next.legalOverlay = next.legalOverlay.withoutStatus(requirement)
            next.legalOverlay.notes[requirement] = nil
        }
        working = next
        finalizationIssues = []
        finalizationError = false
        scheduleSave()
    }

    func reversibleEdit(_ kind: UndoKind, evidenceNames: [String] = [], _ transform: (HandoverProtocol) -> HandoverProtocol) {
        if contentLocked { return }
        commitUndo()
        guard let before = working else { return }
        let edited = transform(before)
        if edited == before { return }
        if before.signatures.contains(where: { before.isCurrent($0) && !$0.file.isBlank }) {
            edit { _ in edited }
            return
        }
        applyContentEdit(edited, from: before)
        guard let after = working else { return }
        let token = UInt64.random(in: 1...UInt64.max)
        let dir = store.photoDir(before.id)
        let files = evidenceNames.distinct().filter(EvidenceNames.isSafe).map { dir.appendingPathComponent($0) }
        pendingUndo = PendingUndo(token: token, before: before, afterRevision: after.contentRevision, files: files)
        undoNotice = UndoNotice(token: token, kind: kind)
        undoTask = Task {
            try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 30 : 6))
            if !Task.isCancelled { commitUndo(token) }
        }
    }

    /// An edit whose only cost is entered numbers rather than a record of its own, offered back
    /// through the same undo bar the removals use. "No physical keys" is the one pill that
    /// silently zeroes counts the operator typed by hand.
    func editUndoably(_ transform: (HandoverProtocol) -> HandoverProtocol) {
        reversibleEdit(.keyCounts, transform)
    }

    func undo(_ token: UInt64) {
        guard let pending = pendingUndo, pending.token == token else { return }
        if let current = working, current.id == pending.before.id, current.contentRevision == pending.afterRevision {
            var restored = pending.before
            restored.contentRevision = current.contentRevision + 1
            restored.saveSequence = current.saveSequence
            restored.exportedEpochMs = 0
            restored.details.reviewRevision = -1
            restored.details.legalSnapshot = nil
            working = restored
            undoTask?.cancel()
            pendingUndo = nil
            undoNotice = nil
            scheduleSave()
        } else {
            commitUndo(token)
        }
    }

    func commitUndo(_ token: UInt64? = nil) {
        guard let pending = pendingUndo else { return }
        if let token, pending.token != token { return }
        // Keep removed originals privately until the whole record is deleted. A failed save
        // or last-good recovery may still refer to them. Scoped backups omit unused files.
        undoTask?.cancel()
        undoTask = nil
        pendingUndo = nil
        undoNotice = nil
    }

    var contentLocked: Bool { working?.isFinalized() == true || finalizing }

    /// Ink records agreement with the current draft; it does not itself rewrite the draft.
    func editSignatures(_ transform: (HandoverProtocol) -> HandoverProtocol) {
        commitUndo()
        guard let p = working, !p.isFinalized(), !finalizing else { return }
        let edited = transform(p)
        if edited == p { return }
        working = edited
        finalizationIssues = []
        finalizationError = false
        scheduleSave()
    }

    /// Metadata captured after finalization, such as handing over an identical copy.
    func editMetadata(_ transform: (HandoverProtocol) -> HandoverProtocol) {
        commitUndo()
        guard let p = working else { return }
        working = transform(p)
        scheduleSave()
    }

    func recordDelivery(_ role: Role, method: DeliveryMethod, note: String = "") {
        guard let p = working, p.isFinalized(), p.isExported(), [Role.tenant, .landlord].contains(role) else { return }
        if method == .other, note.isBlank { return }
        let changedAt = Int64(Date().timeIntervalSince1970 * 1000)
        editMetadata { record in
            var next = record
            next.deliveryReceipts = record.deliveryReceipts.filter { $0.role != role } +
                [DeliveryReceipt(role, epochMs: changedAt, method: method, note: note.trimmingCharacters(in: .whitespacesAndNewlines))]
            next.deliveryMetadataEpochMs = changedAt
            next.deliveryRevision += 1
            return next
        }
    }

    func clearDelivery(_ role: Role) {
        guard working?.isFinalized() == true else { return }
        editMetadata { record in
            var next = record
            next.deliveryReceipts = record.deliveryReceipts.filter { $0.role != role }
            next.deliveryMetadataEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
            next.deliveryRevision += 1
            return next
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            do { try await Task.sleep(for: saveDelay) } catch { return }
            guard !Task.isCancelled else { return }
            persistWorking()
        }
    }

    /// All model writes enter this owner on the main actor. The store rejects stale sequences
    /// as a second boundary for finalization and imported metadata writers.
    @discardableResult
    func persistWorking() -> Bool {
        guard var p = working else { return true }
        guard !finalizing else { return false }
        p.saveSequence += 1
        working = p
        do {
            try store.save(p)
            saveError = nil
            return true
        } catch {
            saveError = str.saveFailed + " (\(error.localizedDescription))"
            return false
        }
    }

    @discardableResult
    func flush() -> Bool {
        commitUndo()
        saveTask?.cancel()
        saveTask = nil
        guard persistWorking() else { return false }
        prefs.set(flowStep.rawValue, forKey: keyStep)
        prefs.set(openRoomId, forKey: keyRoom)
        prefs.set(editingDefectId, forKey: keyDefect)
        return true
    }

    static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// Starts the walk only after the new-session form has supplied a complete validated identity.
    func startNewSession(role: Role, identity: SessionIdentity, kind: Kind) {
        guard identity.hasRequiredFields() else { return }
        chooseRole(role, name: identity.fullName, company: identity.company)
        createProtocol(kind, sessionRole: role, sessionName: identity.fullName, sessionIdentity: identity)
    }

    func controllerFor(_ identity: SessionIdentity) -> ControllerIdentity {
        if !controllerIdentity.isBlank { return controllerIdentity }
        var controller = ControllerIdentity()
        controller.organisation = identity.company
        controller.contactName = identity.fullName
        controller.street = identity.addressLine
        controller.postalCode = identity.postalCode
        controller.city = identity.city
        controller.phone = identity.phone
        return controller
    }

    func createProtocol(_ kind: Kind, sessionRole: Role?, sessionName: String, sessionIdentity: SessionIdentity) {
        guard flush() else { return }
        let now = Self.now()
        let resolvedName = sessionIdentity.fullName.ifBlank(sessionName.trimmingCharacters(in: .whitespacesAndNewlines))
        var resolvedIdentity = sessionIdentity
        resolvedIdentity.phone = InternationalPhone.format(sessionIdentity.phone, regionCode: sessionIdentity.phoneRegion)
        var p = HandoverProtocol(id: "p\(now)", kind: kind, createdEpochMs: now)
        p.sessionRole = sessionRole
        p.sessionName = resolvedName
        p.sessionIdentity = resolvedIdentity
        p.controllerIdentity = controllerFor(resolvedIdentity)
        // The object is the flat being handed over, not the starter's contact address. It is
        // entered independently from the official swisstopo lookup in the dossier.
        p.handoverDate = LocalDate.today().isoString
        var tenant = Party(.tenant)
        if sessionRole == .tenant {
            tenant.name = resolvedName
            // At an exit the starter's contact address IS the new address the deposit letter goes
            // to, so it reaches the form's "Neue Adresse" field directly.
            if kind == .exit {
                tenant.address = [resolvedIdentity.addressLine, resolvedIdentity.placeLine].filter { !$0.isBlank }.joined(separator: ", ")
            }
            tenant.phone = resolvedIdentity.phone
        }
        // An agency is the representative, never a substitute for the contractual landlord.
        var landlord = Party(.landlord)
        if sessionRole == .landlord {
            landlord.name = resolvedIdentity.company.isBlank ? resolvedName : ""
            landlord.agency = resolvedIdentity.company
            landlord.representedBy = resolvedIdentity.company.isBlank ? "" : resolvedName
            landlord.phone = resolvedIdentity.phone
        }
        tenant.id = UUID().uuidString
        landlord.id = UUID().uuidString
        p.parties = [tenant, landlord]
        saveReusableIdentity(resolvedIdentity)
        p.keys = [KeyCount(.apartment), KeyCount(.houseDoor), KeyCount(.mailbox), KeyCount(.cellar)]
        p.dossier = [.keys]
        setActiveProtocol(p)
        persistWorking()
        flowStep = .hub
        openRoomId = nil
        prefs.set(p.id, forKey: keyOpen)
    }

    /// The flat's rooms carry over as the buttons of the exit walk; nothing recorded inside them
    /// does. An older entry's item grid is dropped rather than reopened: the exit is a new record
    /// and records only what it finds.
    static func freshRoom(_ room: Room) -> Room {
        var fresh = room
        fresh.items = []
        fresh.keysCount = 0
        fresh.inspected = false
        return fresh
    }

    /// The supplied object is still supplied; the photographs of it at entry are not its exit state.
    static func freshObject(_ entry: ObjectEntry) -> ObjectEntry {
        var fresh = entry
        fresh.photos = []
        fresh.photoEvidence = []
        fresh.inspected = false
        return fresh
    }

    /// Opens an exit from its entry baseline while retaining the new starter's verified contact data.
    func seedExitFrom(_ entry: HandoverProtocol, sessionRole: Role, identity: SessionIdentity) {
        guard identity.hasRequiredFields(), entry.isFinalized() else { return }
        let name = identity.fullName
        var resolvedIdentity = identity
        resolvedIdentity.phone = InternationalPhone.format(identity.phone, regionCode: identity.phoneRegion)
        chooseRole(sessionRole, name: name, company: identity.company)
        guard flush() else { return }
        let now = Self.now()
        var p = entry
        p.id = "p\(now)"
        p.kind = .exit
        p.sessionRole = sessionRole
        p.sessionName = name
        p.sessionIdentity = resolvedIdentity
        p.controllerIdentity = controllerFor(resolvedIdentity)
        p.createdEpochMs = now
        p.handoverDate = LocalDate.today().isoString
        p.handoverTime = ""
        p.lastProtocolDate = entry.handoverDate
        p.parties = entry.partiesForExit(role: sessionRole, identity: resolvedIdentity).map { party in
            var next = party
            if next.id.isBlank { next.id = UUID().uuidString }
            return next
        }
        p.details = RecordDetails(municipality: entry.details.municipality, district: entry.details.district,
                                  habitableRooms: entry.details.habitableRooms, notificationDays: entry.details.notificationDays,
                                  notificationClause: entry.details.notificationClause,
                                  accessDevices: entry.details.accessDevices.map { device in
                                      var next = device
                                      next.expected = device.transferred
                                      next.transferred = 0
                                      next.note = ""
                                      return next
                                  }, understoodLanguage: entry.details.understoodLanguage)
        p.saveSequence = 0
        p.deliveryRevision = 0
        p.exportHistory = []
        saveReusableIdentity(resolvedIdentity)
        p.rooms = entry.rooms.map(Self.freshRoom)
        p.roomSetupComplete = true
        p.objects = entry.objects.map(Self.freshObject)
        p.defects = []
        p.remarks = ""
        p.chargesStatementBy = ""
        p.oneSided = false
        p.unilateralReason = nil
        p.unilateralNote = ""
        p.legalOverlay = LegalOverlayRecord()
        p.keyTransfer = .notRecorded
        p.keyTransferNote = ""
        p.pendingRecordReservations = OrderedMap()
        p.signatures = []
        p.seedId = entry.id
        p.amendedFromId = ""
        p.contentRevision = 0
        p.finalizedEpochMs = 0
        p.evidenceFingerprint = ""
        p.deliveryReceipts = []
        p.deliveryMetadataEpochMs = 0
        p.exportedEpochMs = 0
        p.meters = Meters()
        setActiveProtocol(p)
        persistWorking()
        flowStep = .hub
        openRoomId = nil
        prefs.set(p.id, forKey: keyOpen)
    }

    func openProtocol(_ id: String) {
        guard flush() else { return }
        guard let p = store.load(id) else { return }
        setActiveProtocol(p)
        // A reopened record opens on its hub whether it is signed or not. A finalized one used
        // to open straight onto Export with every way back out of the flow, which made the
        // signed protocol the one thing in the app nobody could go back and read.
        flowStep = .hub
        openRoomId = nil
        prefs.set(id, forKey: keyOpen)
    }

    func deleteProtocol(_ id: String) {
        let deleted = protocols.first { $0.id == id } ?? store.load(id)
        store.delete(id)
        refreshLibrary()
        // A draft belongs to the person who started this one handover. Once it is discarded, ask
        // who holds the phone again instead of carrying that session's side forward.
        if let deleted, !deleted.isFinalized() { clearProfile() }
    }

    func closeFlow() {
        guard flush() else { return }
        setActiveProtocol(nil)
        if libraryProtectionEnabled && !libraryUnlocked { homePage = .landing }
        editingDefectId = nil
        openRoomId = nil
        flowTrail = []
        // Per-record view state, cleared with the record. The comparison sheet used to survive
        // the close and paint itself over the next protocol opened.
        showDepositCompare = false
        finalizationIssues = []
        finalizationError = false
        prefs.removeObject(forKey: keyOpen)
        prefs.removeObject(forKey: keyStep)
        prefs.removeObject(forKey: keyRoom)
        prefs.removeObject(forKey: keyDefect)
        refreshLibrary()
    }

    /// Every place is reachable in every state. A finalized record is walked exactly like a
    /// draft and refuses every edit instead, which `edit` enforces at the one point all writes
    /// pass through. Locking the navigation as well was belt and braces that cost the reading.
    func goTo(_ step: FlowStep) {
        if step == flowStep { return }
        // A trail, not the static parent chain. A finalized record's hub opens the document
        // directly, and following parents back out of it cost three presses to undo one tap.
        flowTrail = Array((flowTrail + [flowStep]).suffix(maxTrail))
        flowStep = step
        // Leaving the inspection by any route closes the open room.
        if step != .inspection { openRoomId = nil }
    }

    /// The people whose record outcome is required before this phone can freeze the record.
    func requiredRecordRoles(_ p: HandoverProtocol? = nil) -> [Role] {
        guard let record = p ?? working else { return [] }
        return CompletionRules.requiredRecordRoles(record, fallbackRole: myRole)
    }

    func completionIssues(_ p: HandoverProtocol? = nil) -> [FinalizationIssue] {
        guard let record = p ?? working else { return [] }
        if record.isFinalized() { return [] }
        var issues = CompletionRules.protocolCompletionIssues(record, requiredRoles: requiredRecordRoles(record), photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id))
        if (try? EvidenceValidation.requireReadable(record, photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id))) == nil { issues.append(.evidence) }
        return issues.distinct()
    }

    func finalizeProtocol() {
        guard let p = working, !p.isFinalized(), !finalizing else { return }
        let issues = completionIssues(p)
        finalizationIssues = issues
        finalizationError = false
        if !issues.isEmpty { return }
        finalizing = true
        saveTask?.cancel()
        saveTask = nil
        let store = store
        Task {
            let result: Result<HandoverProtocol, Error> = await Task.detached {
                Result {
                    try EvidenceValidation.requireReadable(p, photoDir: store.photoDir(p.id), signatureDir: store.signatureDir(p.id))
                    var withMoment = p
                    withMoment.saveSequence += 1
                    withMoment.signatures = p.signatures.filter { p.isCurrent($0) || $0.plane == .costs }
                    withMoment.details.legalSnapshot = p.freezeLegalRules()
                    withMoment.pendingRecordReservations = OrderedMap()
                    withMoment.finalizedEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
                    var frozen = withMoment
                    frozen.evidenceFingerprint = try ProtocolIntegrity.fingerprint(withMoment, photoDir: store.photoDir(withMoment.id), signatureDir: store.signatureDir(withMoment.id))
                    try store.save(frozen)
                    return frozen
                }
            }.value
            finalizing = false
            guard working?.id == p.id else { return }
            switch result {
            case .success(let frozen):
                setActiveProtocol(frozen)
                finalizationIssues = []
                flowStep = .export
            case .failure:
                finalizationError = true
            }
        }
    }

    /// Starts a new draft and copies the original photos; the finalized record stays intact.
    func createAmendment() {
        guard let p = working, p.isFinalized(), !amendmentInProgress else { return }
        // The one protocol switch that had no flush before it: a debounced write still in the
        // air would have been aimed at the record being left.
        guard flush() else { return }
        amendmentInProgress = true
        amendmentError = false
        let store = store
        Task {
            let result: Result<HandoverProtocol, Error> = await Task.detached {
                Result {
                    let now = Int64(Date().timeIntervalSince1970 * 1000)
                    var draft = p
                    draft.id = "p\(now)"
                    draft.createdEpochMs = now
                    draft.amendedFromId = p.id
                    draft.amendedFromFingerprint = p.evidenceFingerprint
                    draft.contentRevision = 0
                    draft.finalizedEpochMs = 0
                    draft.evidenceFingerprint = ""
                    draft.deliveryReceipts = []
                    draft.deliveryMetadataEpochMs = 0
                    draft.signatures = []
                    draft.exportedEpochMs = 0
                    draft.saveSequence = 1
                    draft.deliveryRevision = 0
                    draft.exportHistory = []
                    draft.details.legalSnapshot = nil
                    draft.details.reviewRevision = -1
                    let sourceDir = store.photoDir(p.id)
                    let targetDir = store.photoDir(draft.id)
                    for source in (try? FileManager.default.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)) ?? [] {
                        try FileManager.default.copyItem(at: source, to: targetDir.appendingPathComponent(source.lastPathComponent))
                    }
                    try store.save(draft)
                    return draft
                }
            }.value
            amendmentInProgress = false
            guard working?.id == p.id else { return }
            switch result {
            case .success(let draft):
                setActiveProtocol(draft)
                finalizationIssues = []
                flowStep = .hub
                prefs.set(draft.id, forKey: keyOpen)
            case .failure:
                amendmentError = true
            }
        }
    }

    /// Back inside the flow: out of the open room, then up the one branch a step has.
    func flowBack() {
        if editingDefectId != nil {
            // Through closeDefect, not by clearing the id: leaving the editor by the masthead
            // key used to strand an empty finding on the record.
            closeDefect()
            return
        }
        if flowStep == .inspection, openRoomId != nil {
            openRoomId = nil
            return
        }
        if let trailed = flowTrail.last {
            flowTrail.removeLast()
            flowStep = trailed
            if trailed != .inspection { openRoomId = nil }
            return
        }
        if let parent = flowStep.parent { flowStep = parent } else { closeFlow() }
    }

}
