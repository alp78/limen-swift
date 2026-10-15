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

    private func read(_ file: URL, id: String) -> HandoverProtocol? {
        guard EvidenceNames.isArchiveSafe(id), Files.isRegularFile(file), Files.size(file) <= 8 * 1024 * 1024,
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

    public func exportArchive(password: String, to output: URL, protocolIds: Set<String>? = nil) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        try ArchiveCrypto.export(root: root, password: password, to: output, protocolIds: protocolIds)
    }

    public func importArchive(password: String, from input: URL, repairCorrupt: Bool = false) throws -> ArchiveImportResult {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return try ArchiveCrypto.importArchive(root: root, password: password, from: input, repairCorrupt: repairCorrupt)
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
