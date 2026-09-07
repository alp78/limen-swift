import Foundation
import LimenKit
import Observation
import UIKit

private let keyDark = "darkTheme"
private let keyLang = "lang"
private let keyOpen = "openProtocol"
private let keyStep = "openStep"
private let keyRoom = "openRoom"
private let keyDefect = "openDefect"
private let keyRole = "myRole"
private let keyName = "profileName"
private let keyCompany = "profileCompany"
private let keyControllerOrganisation = "controllerOrganisation"
private let keyControllerContact = "controllerContact"
private let keyControllerStreet = "controllerStreet"
private let keyControllerPostal = "controllerPostalCode"
private let keyControllerCity = "controllerCity"
private let keyControllerEmail = "controllerEmail"
private let keyControllerPhone = "controllerPhone"

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
    private let prefs: UserDefaults
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
    var archiveBusy = false
    var archiveExported: ExportedFile?
    /// Whether the last export carried a password, so the screen can say when it did not.
    var archiveProtected = true
    var archiveImported: ArchiveImportResult?
    var archiveFailed = false

    // MARK: The flow

    /// The protocol being walked, or nil when the case is showing. Saved on every edit.
    var working: HandoverProtocol?
    /// The entry record shown beside an exit inspection, never copied into the mutable exit.
    var entryBaseline: HandoverProtocol?
    var flowStep: FlowStep = .hub
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
        protocols = store.list()
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
            if !Task.isCancelled { notice = nil }
        }
    }

    // MARK: Archive

    func exportArchive(password: String) {
        if archiveBusy { return }
        flush()
        archiveProtected = !password.isEmpty
        archiveBusy = true
        archiveExported = nil
        archiveImported = nil
        archiveFailed = false
        let store = store
        let name = "Limen-backup-\(Exports.stamp()).limen"
        Task {
            let result: Result<ExportedFile, Error> = await Task.detached {
                Result { try Exports.write(name: name) { url in try store.exportArchive(password: password, to: url) } }
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
        flush()
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
                protocols = store.list()
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
        exportIssue = nil
        pdfLang = nil
        defectShell = nil
        flowTrail = []
        working = p
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
        let edited = transform(p)
        if edited == p { return }
        var next = edited
        next.contentRevision = p.contentRevision + 1
        next.exportedEpochMs = 0
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
        var after = edited
        after.contentRevision = before.contentRevision + 1
        after.exportedEpochMs = 0
        let token = DispatchTime.now().uptimeNanoseconds
        let dir = store.photoDir(before.id)
        let files = evidenceNames.distinct().filter(EvidenceNames.isSafe).map { dir.appendingPathComponent($0) }
        working = after
        pendingUndo = PendingUndo(token: token, before: before, afterRevision: after.contentRevision, files: files)
        undoNotice = UndoNotice(token: token, kind: kind)
        finalizationIssues = []
        finalizationError = false
        scheduleSave()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(6))
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
            restored.exportedEpochMs = 0
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
        for file in pending.files { try? FileManager.default.removeItem(at: file) }
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
            return next
        }
    }

    func clearDelivery(_ role: Role) {
        guard working?.isFinalized() == true else { return }
        editMetadata { record in
            var next = record
            next.deliveryReceipts = record.deliveryReceipts.filter { $0.role != role }
            next.deliveryMetadataEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
            return next
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        let store = store
        saveTask = Task {
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled, let p = working else { return }
            await Task.detached { try? store.save(p) }.value
        }
    }

    /// The draft on disk, now. Called when the app leaves the foreground, when the flow closes
    /// and before any protocol is read back, so the debounce above can never be the reason a
    /// keystroke was lost. It writes on the calling thread on purpose: these are lifecycle edges,
    /// not typing.
    func flush() {
        commitUndo()
        saveTask?.cancel()
        saveTask = nil
        guard let p = working, !finalizing else { return }
        try? store.save(p)
        // The place in the walk is part of what "still open" means. The camera routinely
        // suspends this process while the shutter is open, and coming back to the case home
        // instead of the room being photographed is the moment the picture reads as lost.
        prefs.set(flowStep.rawValue, forKey: keyStep)
        prefs.set(openRoomId, forKey: keyRoom)
        prefs.set(editingDefectId, forKey: keyDefect)
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
        flush()
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
        // An agency session puts the firm on the landlord line and the person present behind
        // "vertreten durch", the way the paper forms record a Verwaltung.
        var landlord = Party(.landlord)
        if sessionRole == .landlord {
            landlord.name = resolvedIdentity.company.isBlank ? resolvedName : resolvedIdentity.company
            landlord.representedBy = resolvedIdentity.company.isBlank ? "" : resolvedName
            landlord.phone = resolvedIdentity.phone
        }
        p.parties = [tenant, landlord]
        p.keys = [KeyCount(.apartment), KeyCount(.houseDoor), KeyCount(.mailbox), KeyCount(.cellar)]
        p.dossier = [.keys]
        try? store.save(p)
        setActiveProtocol(p)
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
        flush()
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
        p.parties = entry.parties.map { party in
            var next = party
            if party.role != sessionRole { return party }
            if sessionRole == .landlord, !resolvedIdentity.company.isBlank {
                // The agency's exit session: firm on the landlord line, the person sent behind
                // "vertreten durch", matching how createProtocol writes an agency entry.
                next.name = resolvedIdentity.company
                next.representedBy = name
                next.phone = resolvedIdentity.phone
            } else if sessionRole == .tenant {
                // The leaving tenant's contact address is the new address of the exit form.
                next.name = name
                next.address = [resolvedIdentity.addressLine, resolvedIdentity.placeLine].filter { !$0.isBlank }.joined(separator: ", ")
                next.phone = resolvedIdentity.phone
            } else {
                next.name = name
                next.phone = resolvedIdentity.phone
            }
            return next
        }
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
        try? store.save(p)
        setActiveProtocol(p)
        flowStep = .hub
        openRoomId = nil
        prefs.set(p.id, forKey: keyOpen)
    }

    func openProtocol(_ id: String) {
        flush()
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
        protocols = store.list()
        // A draft belongs to the person who started this one handover. Once it is discarded, ask
        // who holds the phone again instead of carrying that session's side forward.
        if let deleted, !deleted.isFinalized() { clearProfile() }
    }

    func closeFlow() {
        flush()
        setActiveProtocol(nil)
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
        protocols = store.list()
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
        return CompletionRules.protocolCompletionIssues(record, requiredRoles: requiredRecordRoles(record), photoDir: store.photoDir(record.id), signatureDir: store.signatureDir(record.id))
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
                    var withMoment = p
                    withMoment.signatures = p.signatures.filter(p.isCurrent)
                    withMoment.pendingRecordReservations = OrderedMap()
                    withMoment.finalizedEpochMs = Int64(Date().timeIntervalSince1970 * 1000)
                    var frozen = withMoment
                    frozen.evidenceFingerprint = try ProtocolIntegrity.fingerprint(withMoment, photoDir: store.photoDir(withMoment.id), signatureDir: store.signatureDir(withMoment.id))
                    try store.save(frozen)
                    return frozen
                }
            }.value
            finalizing = false
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
        flush()
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

    // MARK: A record for the smoke

    #if DEBUG
    /// Under `LIMEN_DEMO`, the draft the Android instrumentation seeded before its walk: an entry
    /// in Vaud with its overlay answered, two named parties, one room and the keys card.
    static func seedDemo(into store: Store, prefs: UserDefaults) {
        var p = HandoverProtocol(id: "navigation-draft", kind: .entry, createdEpochMs: 1)
        p.sessionRole = .tenant
        p.sessionName = "Test tenant"
        p.address = "Test street 1"
        p.place = "1000 Test"
        p.objectCanton = .vd
        p.legalOverlay = LegalOverlayRecord().withStatus(.leaseAndLocalTiming, .confirmed).withStatus(.vaudExitReadiness, .confirmed)
        p.handoverDate = "2026-08-18"
        p.handoverTime = "10:00"
        p.contract.conclusionDate = "2026-07-01"
        p.parties = [Party(.tenant, name: "Test tenant"), Party(.landlord, name: "Test landlord")]
        p.rooms = [Room(id: "r1", kind: .room)]
        p.dossier = [.keys]
        p.keyTransfer = .noPhysicalKeys
        try? store.save(p)
        prefs.set(p.id, forKey: keyOpen)
        prefs.set("Tenant", forKey: keyRole)
        prefs.set("Test tenant", forKey: keyName)
    }

    static func resetForTests(prefs: UserDefaults, root: URL) {
        for key in [keyDark, keyLang, keyOpen, keyStep, keyRoom, keyDefect, keyRole, keyName, keyCompany] { prefs.removeObject(forKey: key) }
        for item in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: item)
        }
    }
    #endif
}
