import Foundation

public struct ArchiveImportResult: Hashable, Sendable {
    public let imported: Int
    public let skippedExisting: Int
    public let rejected: Int
    public let repairable: Int
    public let repaired: Int
    public init(imported: Int, skippedExisting: Int, rejected: Int, repairable: Int = 0, repaired: Int = 0) {
        self.imported = imported; self.skippedExisting = skippedExisting; self.rejected = rejected
        self.repairable = repairable; self.repaired = repaired
    }
}

public enum ArchiveError: Error, Equatable {
    case notALimenArchive, invalidEntry(String), manifestMissing
    case emptyPassword, randomUnavailable, unsupportedVersion, truncated, wrongPassword, destinationExists
    case unreadableRecord(String), insufficientStorage, missingExport(String)
    /// A version 2 backup holds repacked photographs and this build has nothing to rebuild them with.
    case packedPhotographsUnsupported
    /// A repacked photograph does not rebuild, so nothing of the backup is installed.
    case packedPhotographUnreadable(String)
}

/// Sweep only files from an earlier run. Another live operation may be using the same cache.
enum ArchiveStaging {
    private static let processStart = Date()
    static func sweep(_ root: URL, prefix: String) {
        let cutoff = processStart
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            guard url.lastPathComponent.hasPrefix(prefix),
                  let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  date < cutoff else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

/// Versioned, local-only backup of protocol JSON and its original evidence files.
///
/// No size or count limit, on this side or on import: a cap of 64 MiB refused a single record of
/// thirty camera originals, which weigh 69 MB, and the only bound a backup meets is the storage it
/// is written to and restored onto, which `FreeSpace` asks for once per megabyte.
enum ArchiveIO {
    static let manifest = "limen-archive.txt"
    static let marker = "LIMEN_ARCHIVE\nversion=1\n"
    /// A backup holding repacked photographs. One with none stays version 1, which 1.2.4 and
    /// earlier restore; those refuse version 2 as not a Limen archive, and install nothing.
    static let markerPacked = "LIMEN_ARCHIVE\nversion=2\n"
    /// `jpegxl/<record>/<file>` holds photograph `photos/<record>/<file>` repacked by a `JpegPacker`.
    static let packed = "jpegxl"
    private static let jpegStart: [UInt8] = [0xFF, 0xD8, 0xFF]
    private static let stagePrefix = ".archive-import-"

    /// Each JPEG photograph goes in repacked by `packer` when that comes out smaller and unpacks to
    /// the very same bytes; anything else goes in as it is.
    static func export(root: URL, to output: URL, protocolIds: Set<String>? = nil, packer: (any JpegPacker)? = JpegXL.loaded) throws {
        let store = Store(root: root)
        let catalogue = store.catalogue()
        if let failure = catalogue.unreadable.first(where: { (protocolIds?.contains($0.id) ?? true) }) {
            throw ArchiveError.unreadableRecord(failure.id)
        }
        if let protocolIds, !protocolIds.isSubset(of: Set(catalogue.records.map(\.id))) {
            throw ArchiveError.unreadableRecord(protocolIds.subtracting(catalogue.records.map(\.id)).sorted().joined(separator: ", "))
        }
        let zip = try Zip.Writer(to: output)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: output) } }
        var packedAny = false
        func put(_ name: String, _ file: URL) throws {
            guard isAllowed(name), Files.isRegularFile(file) else { throw ArchiveError.invalidEntry(name) }
            try zip.put(name, file: file)
        }
        for p in catalogue.records.filter({ (protocolIds?.contains($0.id) ?? true) }) {
            let photos = root.appendingPathComponent("photos/\(p.id)")
            let ink = root.appendingPathComponent("signatures/\(p.id)")
            try EvidenceValidation.requireReadable(p, photoDir: photos, signatureDir: ink)
            guard !p.isFinalized() || ProtocolIntegrity.matches(p, photoDir: photos, signatureDir: ink) else {
                throw ArchiveError.unreadableRecord(p.id)
            }
            try put("protocols/\(p.id).json", root.appendingPathComponent("protocols/\(p.id).json"))
            for name in (p.allPhotoFiles() + p.details.attachments.map(\.file)).filter({ !$0.isBlank }).distinct() {
                let file = photos.appendingPathComponent(name)
                guard isAllowed("photos/\(p.id)/\(name)"), Files.isRegularFile(file) else { throw ArchiveError.invalidEntry(name) }
                // A pool per photograph: the JPEG, its repacked form and the check decode are
                // each a few megabytes, and the loop runs on the main actor until the export ends.
                let repacked = try autoreleasepool { packer == nil ? nil : try repack(packer.unsafelyUnwrapped, file) }
                if let repacked {
                    try zip.put("\(packed)/\(p.id)/\(name)", bytes: repacked, stored: true)
                    packedAny = true
                } else {
                    try put("photos/\(p.id)/\(name)", file)
                }
            }
            for name in p.signatures.map(\.file).filter({ !$0.isBlank }).distinct() {
                try put("signatures/\(p.id)/\(name)", ink.appendingPathComponent(name))
            }
            let exports = root.appendingPathComponent("exports/\(p.id)")
            guard validExports(p, directory: exports) else { throw ArchiveError.missingExport(p.id) }
            for name in exportNames(p, directory: exports) { try put("exports/\(p.id)/\(name)", exports.appendingPathComponent(name)) }
        }
        // Last, because only now is it known whether anything was repacked.
        try zip.put(manifest, bytes: Data((packedAny ? markerPacked : marker).utf8))
        try zip.finish()
        completed = true
    }

    /// `file` repacked, or nil when it is not a JPEG, does not come out smaller, or does not
    /// unpack to the same bytes. libjxl's maintainers count about one JPEG in a hundred that it
    /// refuses, and the check costs one unpack per photograph: a backup never holds a photograph
    /// it cannot give back exactly. One photograph is held whole at a time, as on Android.
    /// Above this a file is not a photograph a phone took, and it travels as it is: libjxl needs
    /// the whole JPEG in memory to transcode it, and reading a gigabyte that starts with the JPEG
    /// marker was the one place the export still held a file whole on the phone.
    static let repackLimit: Int64 = 64 * 1024 * 1024

    private static func repack(_ packer: any JpegPacker, _ file: URL) throws -> Data? {
        // The first bytes alone, so a large supporting PDF is never read into memory to be skipped.
        guard Files.size(file) <= repackLimit else { return nil }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        guard let head = try handle.read(upToCount: 3), [UInt8](head) == jpegStart else { return nil }
        let jpeg = try Data(contentsOf: file)
        guard let repacked = packer.pack(jpeg), repacked.count < jpeg.count, packer.unpack(repacked) == jpeg else { return nil }
        return repacked
    }

    static func importArchive(root: URL, from input: URL, repairCorrupt: Bool = false, packer: (any JpegPacker)? = JpegXL.loaded) throws -> ArchiveImportResult {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ArchiveStaging.sweep(root, prefix: stagePrefix)
        let stage = root.appendingPathComponent("\(stagePrefix)\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        try unpack(into: stage, from: input, packer: packer)
        let text = try? String(contentsOf: stage.appendingPathComponent(manifest), encoding: .utf8)
        guard text == marker || text == markerPacked else { throw ArchiveError.notALimenArchive }
        return try installValidated(root: root, stage: stage, repairCorrupt: repairCorrupt)
    }

    private static func unpack(into stage: URL, from input: URL, packer: (any JpegPacker)?) throws {
        let reader = try Zip.Reader(input)
        var seen = Set<String>()
        let space = FreeSpace(stage)
        for entry in reader.entries {
            let name = entry.name
            // A repacked photograph unpacks to its original's place, and counts as that name.
            let isPacked = name.hasPrefix("\(packed)/")
            let path = isPacked ? "photos/" + name.dropFirst(packed.count + 1) : name
            guard !entry.isDirectory, isAllowed(name), seen.insert(path).inserted else { throw ArchiveError.invalidEntry(name) }
            let target = stage.appendingPathComponent(path)
            if isPacked {
                let bytes = try reader.read(entry)
                guard let packer else { throw ArchiveError.packedPhotographsUnsupported }
                guard let jpeg = packer.unpack(bytes) else { throw ArchiveError.packedPhotographUnreadable(name) }
                try space.before(jpeg.count)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try jpeg.write(to: target)
            } else {
                try reader.extract(entry, to: target, space: space)
            }
        }
        guard seen.contains(manifest) else { throw ArchiveError.manifestMissing }
    }

    static func isAllowed(_ name: String) -> Bool {
        if name == manifest { return true }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard (2...3).contains(parts.count), parts.allSatisfy(EvidenceNames.isArchiveSafe) else { return false }
        switch parts[0] {
        case "protocols": return parts.count == 2 && parts[1].hasSuffix(".json")
        case "photos", "signatures", "exports", packed: return parts.count == 3
        default: return false
        }
    }

    private static func installValidated(root: URL, stage: URL, repairCorrupt: Bool) throws -> ArchiveImportResult {
        let staged = (try? FileManager.default.contentsOfDirectory(at: stage.appendingPathComponent("protocols"), includingPropertiesForKeys: nil)) ?? []
        var imported = 0, skipped = 0, rejected = 0, repairable = 0, repaired = 0
        for source in staged.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let bytes = try? Data(contentsOf: source), let p = try? ProtocolJSON.decode(bytes), EvidenceNames.isArchiveSafe(p.id),
                  source.deletingPathExtension().lastPathComponent == p.id else { rejected += 1; continue }
            let photoRelative = "photos/\(p.id)", inkRelative = "signatures/\(p.id)", exportRelative = "exports/\(p.id)"
            let target = root.appendingPathComponent("protocols/\(p.id).json")
            guard validEvidence(p, photos: stage.appendingPathComponent(photoRelative), ink: stage.appendingPathComponent(inkRelative)),
                  validExports(p, directory: stage.appendingPathComponent(exportRelative)) else { rejected += 1; continue }
            let paths = ["protocols/\(p.id).json", photoRelative, inkRelative, exportRelative]
            var moved: [(URL, URL)] = []
            if FileManager.default.fileExists(atPath: target.path) {
                let old = Store(root: root).load(p.id)
                let healthy = old.map {
                    validEvidence($0, photos: root.appendingPathComponent(photoRelative), ink: root.appendingPathComponent(inkRelative)) &&
                        validExports($0, directory: root.appendingPathComponent(exportRelative))
                } ?? false
                if healthy || !repairCorrupt {
                    skipped += 1
                    if !healthy { repairable += 1 }
                    continue
                }
                let quarantine = root.appendingPathComponent("recovery/\(p.id)/archive-\(UUID().uuidString)")
                do {
                    for path in paths {
                        let original = root.appendingPathComponent(path)
                        if FileManager.default.fileExists(atPath: original.path) {
                            let retained = quarantine.appendingPathComponent(path)
                            try FileManager.default.createDirectory(at: retained.deletingLastPathComponent(), withIntermediateDirectories: true)
                            try FileManager.default.moveItem(at: original, to: retained)
                            moved.append((original, retained))
                        }
                    }
                } catch {
                    for (original, retained) in moved.reversed() { try FileManager.default.moveItem(at: retained, to: original) }
                    rejected += 1; continue
                }
            } else if paths.dropFirst().contains(where: { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }) {
                rejected += 1; continue
            }
            do {
                // Install only referenced evidence. Unrelated archive entries never become private
                // evidence merely because they happened to share the record's directory.
                for name in (p.allPhotoFiles() + p.details.attachments.map(\.file)).filter({ !$0.isBlank }).distinct() {
                    try atomicCopy(stage.appendingPathComponent("\(photoRelative)/\(name)"), to: root.appendingPathComponent("\(photoRelative)/\(name)"))
                }
                for name in p.signatures.map(\.file).filter({ !$0.isBlank }).distinct() {
                    try atomicCopy(stage.appendingPathComponent("\(inkRelative)/\(name)"), to: root.appendingPathComponent("\(inkRelative)/\(name)"))
                }
                for name in exportNames(p, directory: stage.appendingPathComponent(exportRelative)) {
                    try atomicCopy(stage.appendingPathComponent("\(exportRelative)/\(name)"), to: root.appendingPathComponent("\(exportRelative)/\(name)"))
                }
                try atomicCopy(source, to: target)
                imported += 1
                if !moved.isEmpty { repaired += 1 }
            } catch {
                for path in paths { try? FileManager.default.removeItem(at: root.appendingPathComponent(path)) }
                for (original, retained) in moved.reversed() {
                    try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try FileManager.default.moveItem(at: retained, to: original)
                }
                rejected += 1
            }
        }
        return ArchiveImportResult(imported: imported, skippedExisting: skipped, rejected: rejected, repairable: repairable, repaired: repaired)
    }

    private static func validEvidence(_ p: HandoverProtocol, photos: URL, ink: URL) -> Bool {
        EvidenceValidation.unreadable(p, photoDir: photos, signatureDir: ink).isEmpty &&
            ProtocolIntegrity.missingEvidence(p, photoDir: photos, signatureDir: ink).isEmpty &&
            (!p.isFinalized() || ProtocolIntegrity.matches(p, photoDir: photos, signatureDir: ink))
    }

    private static func exportNames(_ p: HandoverProtocol, directory: URL) -> [String] {
        p.exportHistory.flatMap { copy -> [String] in
            let html = (copy.name as NSString).deletingPathExtension + ".html"
            return [copy.name] + (Files.isRegularFile(directory.appendingPathComponent(html)) ? [html] : [])
        }.distinct()
    }

    private static func validExports(_ p: HandoverProtocol, directory: URL) -> Bool {
        p.exportHistory.allSatisfy { copy in
            guard EvidenceNames.isArchiveSafe(copy.name) else { return false }
            let file = directory.appendingPathComponent(copy.name)
            guard Files.isRegularFile(file), Files.size(file) == copy.bytes else { return false }
            if !copy.companionUri.isBlank {
                let companion = directory.appendingPathComponent((copy.name as NSString).deletingPathExtension + ".html")
                guard Files.isRegularFile(companion), Files.size(companion) > 0 else { return false }
            }
            return copy.sha256.isBlank || EvidenceValidation.hashMatches(file, copy.sha256)
        }
    }

    private static func atomicCopy(_ source: URL, to target: URL) throws {
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = target.deletingLastPathComponent().appendingPathComponent("\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.copyItem(at: source, to: tmp)
        try Files.replace(target, with: tmp)
    }
}
