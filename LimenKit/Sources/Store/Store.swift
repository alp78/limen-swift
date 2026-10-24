import Foundation

/// Atomic record persistence, with explicit unreadable entries and reversible recovery.
public final class Store: Sendable {
    public enum SaveError: Error, LocalizedError, Equatable {
        case staleWrite, unsafeIdentifier, unreadablePrevious, invalidRecord
        public var errorDescription: String? {
            switch self {
            case .staleWrite: return "A newer revision is already saved"
            case .unsafeIdentifier: return "The record identifier is invalid"
            case .unreadablePrevious: return "Recover the unreadable record before replacing it"
            case .invalidRecord: return "The record cannot be read without changing its data"
            }
        }
    }
    public struct UnreadableRecord: Hashable, Sendable, Identifiable {
        public let id: String
        public let hasRecovery: Bool
        public init(id: String, hasRecovery: Bool) { self.id = id; self.hasRecovery = hasRecovery }
    }
    public struct Catalogue: Sendable {
        public let records: [HandoverProtocol]
        public let unreadable: [UnreadableRecord]
    }
    public let root: URL
    private let dir: URL
    // Store instances are also created by archives. One process-wide owner prevents two instances
    // from both accepting the same predecessor before either has replaced it.
    private static let lock = NSRecursiveLock()
    /// The roots `sweepStale` has run for, read and written under `lock`.
    nonisolated(unsafe) private static var swept = Set<String>()
    /// The folder an amendment's photographs are copied into before it has a record: swept at
    /// start, since a draft's own folder would sit in no list for good.
    static let amendStage = ".amend-"

    /// What a process killed part way leaves in `root`: the stage and the decrypted copy of a
    /// restore, which only the next restore ever removed, and the half-copied folder of an
    /// amendment. Gigabytes of it, so the caller runs this off the main thread. Once per root
    /// and process: a restore that is running must never find its stage deleted by a second sweep.
    public func sweepStale() {
        Self.lock.lock()
        let first = Self.swept.insert(root.path).inserted
        Self.lock.unlock()
        guard first else { return }
        ArchiveCrypto.sweep(root)
        ArchiveStaging.sweepAll(root.appendingPathComponent("photos"), prefix: Self.amendStage)
    }

    public init(root: URL) {
        self.root = root
        dir = root.appendingPathComponent("protocols")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    public func photoDir(_ id: String) -> URL { directory("photos", id: id) }
    public func signatureDir(_ id: String) -> URL { directory("signatures", id: id) }
    public func exportDir(_ id: String) -> URL { directory("exports", id: id) }

    private func directory(_ name: String, id: String) -> URL {
        let segment = EvidenceNames.isArchiveSafe(id) ? id : ".invalid-identifier"
        let url = root.appendingPathComponent(name).appendingPathComponent(segment)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A foreign URI is descriptive metadata only. Retrieval always resolves the retained name
    /// inside this record's private directory after restoration or a sandbox-path change.
    public func retainedExport(_ id: String, name: String) -> URL? {
        guard EvidenceNames.isArchiveSafe(id), EvidenceNames.isArchiveSafe(name) else { return nil }
        let url = root.appendingPathComponent("exports").appendingPathComponent(id).appendingPathComponent(name)
        return Files.isRegularFile(url) ? url : nil
    }

    public func catalogue() -> Catalogue {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var records: [HandoverProtocol] = []
        var unreadable: [UnreadableRecord] = []
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let id = file.deletingPathExtension().lastPathComponent
            if let p = read(file, id: id) { records.append(p) } else { unreadable.append(UnreadableRecord(id: id, hasRecovery: read(backupURL(id), id: id) != nil)) }
        }
        return Catalogue(records: records.sorted { $0.createdEpochMs > $1.createdEpochMs }, unreadable: unreadable)
    }

    public func list() -> [HandoverProtocol] { catalogue().records }

    public func load(_ id: String) -> HandoverProtocol? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard EvidenceNames.isArchiveSafe(id) else { return nil }
        return read(dir.appendingPathComponent("\(id).json"), id: id)
    }

    // No size cap on a record file: the app must always read back a record it has written.
    private func read(_ file: URL, id: String) -> HandoverProtocol? {
        guard EvidenceNames.isArchiveSafe(id), Files.isRegularFile(file),
              let data = try? Data(contentsOf: file), let p = try? ProtocolJSON.decode(data), p.id == id else { return nil }
        return p
    }

    private func backupURL(_ id: String) -> URL {
        root.appendingPathComponent("recovery").appendingPathComponent(id).appendingPathComponent("last-good.json")
    }

    public static func fileText(_ p: HandoverProtocol) -> String {
        ProtocolJSON.encode(p, encodeDefaults: false).compact
    }

    public func save(_ p: HandoverProtocol) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard EvidenceNames.isArchiveSafe(p.id) else { throw SaveError.unsafeIdentifier }
        let bytes = Data(Self.fileText(p).utf8)
        guard let decoded = try? ProtocolJSON.decode(bytes), decoded == p else { throw SaveError.invalidRecord }
        let target = dir.appendingPathComponent("\(p.id).json")
        let previous = read(target, id: p.id)
        if FileManager.default.fileExists(atPath: target.path), previous == nil { throw SaveError.unreadablePrevious }
        if let old = previous {
            guard p.saveSequence >= old.saveSequence, p.contentRevision >= old.contentRevision,
                  !old.isFinalized() || p.isFinalized(),
                  p.saveSequence == 0 || p.saveSequence != old.saveSequence || Self.fileText(old) == Self.fileText(p) else {
                throw SaveError.staleWrite
            }
            if old.isFinalized(), p.evidenceFingerprint != old.evidenceFingerprint ||
                ProtocolIntegrity.canonicalText(p) != ProtocolIntegrity.canonicalText(old) { throw SaveError.staleWrite }
            // Keep the exact predecessor, including its original text, before replacing it.
            let backup = backupURL(p.id)
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: target).write(to: backup, options: .atomic)
        }
        try atomicWrite(bytes, to: target)
    }

    /// Preserve the damaged original before restoring the last fully readable predecessor.
    @discardableResult
    public func recover(_ id: String) throws -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard EvidenceNames.isArchiveSafe(id) else { throw SaveError.unsafeIdentifier }
        let backup = backupURL(id)
        guard read(backup, id: id) != nil else { return false }
        let target = dir.appendingPathComponent("\(id).json")
        if FileManager.default.fileExists(atPath: target.path) {
            let quarantine = backup.deletingLastPathComponent().appendingPathComponent("original-\(UUID().uuidString).quarantine")
            try FileManager.default.copyItem(at: target, to: quarantine)
        }
        try atomicWrite(Data(contentsOf: backup), to: target)
        return true
    }

    private func atomicWrite(_ data: Data, to target: URL) throws {
        let tmp = dir.appendingPathComponent("\(target.lastPathComponent)-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try data.write(to: tmp)
        let handle = try FileHandle(forWritingTo: tmp)
        do { try handle.synchronize(); try handle.close() } catch { try? handle.close(); throw error }
        try Files.replace(target, with: tmp)
    }

    public func delete(_ id: String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard EvidenceNames.isArchiveSafe(id) else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).json"))
        for folder in ["photos", "signatures", "recovery", "exports"] {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(folder).appendingPathComponent(id))
        }
    }

    /// Saves the draft of an amendment with the photographs and documents it refers to, copied
    /// from `parent`'s folder. What was removed from the parent since stays there for recovery and
    /// is not carried forward. The draft's folder is not a record until its JSON exists, so no
    /// list shows it and no `delete` would ever be asked for it: a failure removes it again here.
    public func saveAmendment(parent: HandoverProtocol, draft: HandoverProtocol) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard EvidenceNames.isArchiveSafe(draft.id) else { throw SaveError.unsafeIdentifier }
        let photos = root.appendingPathComponent("photos")
        // Copied under a name no record has, then renamed into place: a process killed part way
        // leaves a folder that `sweepStale` knows to remove, where the draft's own folder would
        // sit in no list for good.
        let stage = photos.appendingPathComponent("\(Self.amendStage)\(draft.id)")
        do {
            let from = photoDir(parent.id)
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            for name in (parent.allPhotoFiles() + parent.details.attachments.map(\.file)).filter(EvidenceNames.isSafe).distinct() {
                let source = from.appendingPathComponent(name)
                guard Files.isRegularFile(source) else { continue }
                try FileManager.default.copyItem(at: source, to: stage.appendingPathComponent(name))
            }
            try FileManager.default.moveItem(at: stage, to: photos.appendingPathComponent(draft.id))
            try save(draft)
        } catch {
            try? FileManager.default.removeItem(at: stage)
            delete(draft.id)
            throw error
        }
    }

    public func exportArchive(password: String, to output: URL, protocolIds: Set<String>? = nil, packer: (any JpegPacker)? = JpegXL.loaded) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        try ArchiveCrypto.export(root: root, password: password, to: output, protocolIds: protocolIds, packer: packer)
    }

    public func importArchive(password: String, from input: URL, repairCorrupt: Bool = false, packer: (any JpegPacker)? = JpegXL.loaded) throws -> ArchiveImportResult {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try ArchiveCrypto.importArchive(root: root, password: password, from: input, repairCorrupt: repairCorrupt, packer: packer)
    }
}

enum Files {
    /// POSIX rename: atomic on APFS, and it replaces what was there.
    static func replace(_ target: URL, with source: URL) throws {
        if rename(source.path, target.path) != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    static func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func size(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
