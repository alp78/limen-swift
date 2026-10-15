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
    case notALimenArchive, invalidEntry(String), tooManyEntries, tooLarge, manifestMissing
    case emptyPassword, randomUnavailable, unsupportedVersion, truncated, wrongPassword, destinationExists
    case unreadableRecord(String), insufficientStorage, missingExport(String)
}

/// Bounds apply before allocation as well as to bytes actually written. The envelope adds 54
/// bytes to the 64 MiB ZIP ceiling, not another allowance for payload.
enum ArchiveLimits {
    static let payload: Int64 = 64 * 1024 * 1024
    static let expanded: Int64 = 256 * 1024 * 1024
    static let protocolBytes: Int64 = 8 * 1024 * 1024
    static let entries = 20_000
    static let entry: Int64 = 64 * 1024 * 1024
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

enum ArchiveIO {
    static let manifest = "limen-archive.txt"
    static let marker = "LIMEN_ARCHIVE\nversion=1\n"
    private static let stagePrefix = ".archive-import-"

    static func export(root: URL, to output: URL, protocolIds: Set<String>? = nil) throws {
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
        try zip.put(manifest, bytes: Data(marker.utf8))
        var expanded = Int64(marker.utf8.count)
        var entries = 1
        func put(_ name: String, _ file: URL) throws {
            let size = Files.size(file)
            guard isAllowed(name), Files.isRegularFile(file) else { throw ArchiveError.invalidEntry(name) }
            guard size <= (name.hasPrefix("protocols/") ? ArchiveLimits.protocolBytes : ArchiveLimits.entry) else { throw ArchiveError.tooLarge }
            expanded += size; entries += 1
            guard expanded <= ArchiveLimits.expanded, entries <= ArchiveLimits.entries else { throw ArchiveError.tooLarge }
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
                try put("photos/\(p.id)/\(name)", photos.appendingPathComponent(name))
            }
            for name in p.signatures.map(\.file).filter({ !$0.isBlank }).distinct() {
                try put("signatures/\(p.id)/\(name)", ink.appendingPathComponent(name))
            }
            let exports = root.appendingPathComponent("exports/\(p.id)")
            guard validExports(p, directory: exports) else { throw ArchiveError.missingExport(p.id) }
            for name in exportNames(p, directory: exports) { try put("exports/\(p.id)/\(name)", exports.appendingPathComponent(name)) }
        }
        try zip.finish()
        completed = true
    }

    static func importArchive(root: URL, from input: URL, repairCorrupt: Bool = false) throws -> ArchiveImportResult {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ArchiveStaging.sweep(root, prefix: stagePrefix)
        let stage = root.appendingPathComponent("\(stagePrefix)\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        try unpack(into: stage, from: input)
        guard (try? String(contentsOf: stage.appendingPathComponent(manifest), encoding: .utf8)) == marker else { throw ArchiveError.notALimenArchive }
        return try installValidated(root: root, stage: stage, repairCorrupt: repairCorrupt)
    }

    private static func unpack(into stage: URL, from input: URL) throws {
        let reader = try Zip.Reader(input)
        var seen = Set<String>()
        var bytes: Int64 = 0
        guard reader.entries.count <= ArchiveLimits.entries else { throw ArchiveError.tooManyEntries }
        for entry in reader.entries {
            let name = entry.name
            guard !entry.isDirectory, isAllowed(name), seen.insert(name).inserted else { throw ArchiveError.invalidEntry(name) }
            let target = stage.appendingPathComponent(name)
            let ceiling = name.hasPrefix("protocols/") ? ArchiveLimits.protocolBytes : ArchiveLimits.entry
            guard entry.uncompressedSize <= ceiling else { throw ArchiveError.tooLarge }
            bytes += entry.uncompressedSize
            guard bytes <= ArchiveLimits.expanded else { throw ArchiveError.tooLarge }
            let free = (try? FileManager.default.attributesOfFileSystem(forPath: stage.path)[.systemFreeSize] as? NSNumber)?.int64Value
            if let free, free < entry.uncompressedSize + 1024 * 1024 { throw ArchiveError.insufficientStorage }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try reader.read(entry).write(to: target)
        }
        guard seen.contains(manifest) else { throw ArchiveError.manifestMissing }
    }

    static func isAllowed(_ name: String) -> Bool {
        if name == manifest { return true }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard (2...3).contains(parts.count), parts.allSatisfy(EvidenceNames.isArchiveSafe) else { return false }
        switch parts[0] {
        case "protocols": return parts.count == 2 && parts[1].hasSuffix(".json")
        case "photos", "signatures", "exports": return parts.count == 3
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
