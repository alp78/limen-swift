import Foundation

/// The protocol store: one JSON file per protocol under `root/protocols`, photos under
/// `root/photos/<id>`, ink under `root/signatures/<id>`. Plain files in the app's private dir,
/// no database: a handover is a document, documents are files, and files survive schema changes
/// and app reinstalls (via the export) better than any ORM.
///
/// Constructed with a URL rather than the app's own folder, so the round-trip and migration tests
/// run against a scratch folder.
public final class Store: Sendable {
    public let root: URL
    private let dir: URL
    private let lock = NSLock()

    public init(root: URL) {
        self.root = root
        dir = root.appendingPathComponent("protocols")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    public func photoDir(_ id: String) -> URL {
        let url = root.appendingPathComponent("photos").appendingPathComponent(id)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func signatureDir(_ id: String) -> URL {
        let url = root.appendingPathComponent("signatures").appendingPathComponent(id)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func list() -> [HandoverProtocol] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? ProtocolJSON.decode($0) } }
            .sorted { $0.createdEpochMs > $1.createdEpochMs }
    }

    public func load(_ id: String) -> HandoverProtocol? {
        let file = dir.appendingPathComponent("\(id).json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? ProtocolJSON.decode(data)
    }

    /// The store's text: defaults omitted, so a record written before a field existed reads the
    /// same as one written after it.
    public static func fileText(_ p: HandoverProtocol) -> String {
        ProtocolJSON.encode(p, encodeDefaults: false).compact
    }

    public func save(_ p: HandoverProtocol) throws {
        lock.lock()
        defer { lock.unlock() }
        // Keep the previous record until the replacement is fully written. A shared fixed .tmp
        // let a lifecycle flush race the debounce and could leave no readable protocol behind.
        let target = dir.appendingPathComponent("\(p.id).json")
        let tmp = dir.appendingPathComponent("\(p.id)-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data(Self.fileText(p).utf8).write(to: tmp, options: .atomic)
        try Files.replace(target, with: tmp)
    }

    public func delete(_ id: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).json"))
        try? FileManager.default.removeItem(at: root.appendingPathComponent("photos").appendingPathComponent(id))
        try? FileManager.default.removeItem(at: root.appendingPathComponent("signatures").appendingPathComponent(id))
    }

    /// Writes every protocol and its original evidence into an authenticated encrypted archive.
    public func exportArchive(password: String, to output: URL) throws {
        try ArchiveCrypto.export(root: root, password: password, to: output)
    }

    /// Restores encrypted or legacy archives, validates evidence, and never replaces an id.
    public func importArchive(password: String, from input: URL) throws -> ArchiveImportResult {
        try ArchiveCrypto.importArchive(root: root, password: password, from: input)
    }
}

enum Files {
    /// POSIX rename: atomic on APFS, and it replaces what was there.
    static func replace(_ target: URL, with source: URL) throws {
        if rename(source.path, target.path) != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func size(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
