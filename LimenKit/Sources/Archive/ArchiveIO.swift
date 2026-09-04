import Foundation

public struct ArchiveImportResult: Hashable, Sendable {
    public let imported: Int
    public let skippedExisting: Int
    public let rejected: Int

    public init(imported: Int, skippedExisting: Int, rejected: Int) {
        self.imported = imported
        self.skippedExisting = skippedExisting
        self.rejected = rejected
    }
}

public enum ArchiveError: Error, Equatable {
    case notALimenArchive
    case invalidEntry(String)
    case tooManyEntries
    case tooLarge
    case manifestMissing
    case emptyPassword
    case unsupportedVersion
    case truncated
    case wrongPassword
    case destinationExists
}

/// Versioned, local-only backup of protocol JSON and its original evidence files.
enum ArchiveIO {
    static let manifest = "limen-archive.txt"
    static let marker = "LIMEN_ARCHIVE\nversion=1\n"
    private static let maxEntries = 20_000
    private static let stagePrefix = ".archive-import-"
    private static let maxUnpackedBytes: Int64 = 2 * 1024 * 1024 * 1024

    static func export(root: URL, to output: URL) throws {
        let zip = try Zip.Writer(to: output)
        try zip.put(manifest, bytes: Data(marker.utf8))
        for folder in ["protocols", "photos", "signatures"] {
            let base = root.appendingPathComponent(folder)
            guard Files.isDirectory(base) else { continue }
            let files = walk(base)
                .map { (relative: relativePath($0, from: base), url: $0) }
                .sorted { $0.relative.utf16.lexicographicallyPrecedes($1.relative.utf16) }
            for file in files {
                let entryName = "\(folder)/\(file.relative)"
                if isAllowed(entryName) { try zip.put(entryName, file: file.url) }
            }
        }
        try zip.finish()
    }

    static func importArchive(root: URL, from input: URL) throws -> ArchiveImportResult {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // A restore killed part way through leaves its stage behind, and nothing else ever swept
        // them: on a phone that has lost the app mid-import twice, two unpacked copies of the
        // whole archive sat in the private folder for good.
        for item in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        where item.lastPathComponent.hasPrefix(stagePrefix) && Files.isDirectory(item) {
            try? FileManager.default.removeItem(at: item)
        }
        let stage = root.appendingPathComponent("\(stagePrefix)\(UInt64(Date().timeIntervalSince1970 * 1_000_000))")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        try unpack(into: stage, from: input)
        let manifestText = String(decoding: (try? Data(contentsOf: stage.appendingPathComponent(manifest))) ?? Data(), as: UTF8.self)
        guard manifestText == marker else { throw ArchiveError.notALimenArchive }
        return try installValidated(root: root, stage: stage)
    }

    private static func unpack(into stage: URL, from input: URL) throws {
        let reader = try Zip.Reader(input)
        var seen = Set<String>()
        var entries = 0
        var bytes: Int64 = 0
        var hasManifest = false
        let stagePath = stage.standardizedFileURL.path + "/"
        for entry in reader.entries {
            entries += 1
            guard entries <= maxEntries else { throw ArchiveError.tooManyEntries }
            let name = entry.name
            guard !entry.isDirectory, isAllowed(name), seen.insert(name).inserted else { throw ArchiveError.invalidEntry(name) }
            let target = stage.appendingPathComponent(name).standardizedFileURL
            guard target.path.hasPrefix(stagePath) else { throw ArchiveError.invalidEntry(name) }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            bytes += entry.uncompressedSize
            guard bytes <= maxUnpackedBytes else { throw ArchiveError.tooLarge }
            let data = try reader.read(entry)
            try data.write(to: target)
            if name == manifest { hasManifest = true }
        }
        guard hasManifest else { throw ArchiveError.manifestMissing }
    }

    static func isAllowed(_ name: String) -> Bool {
        if name == manifest { return true }
        if name.contains("\\") || name.hasPrefix("/") || name.contains("../") { return false }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard (2...3).contains(parts.count) else { return false }
        switch parts[0] {
        case "protocols": return parts.count == 2 && parts[1].hasSuffix(".json") && EvidenceNames.isArchiveSafe(parts[1])
        case "photos", "signatures": return parts.count == 3 && EvidenceNames.isArchiveSafe(parts[1]) && EvidenceNames.isArchiveSafe(parts[2])
        default: return false
        }
    }

    private static func installValidated(root: URL, stage: URL) throws -> ArchiveImportResult {
        let stagedProtocols = ((try? FileManager.default.contentsOfDirectory(at: stage.appendingPathComponent("protocols"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent.utf16.lexicographicallyPrecedes($1.lastPathComponent.utf16) }
        var imported = 0
        var skipped = 0
        var rejected = 0

        for sourceJson in stagedProtocols {
            let record = (try? Data(contentsOf: sourceJson)).flatMap { try? ProtocolJSON.decode($0) }
            guard let record, EvidenceNames.isArchiveSafe(record.id), sourceJson.deletingPathExtension().lastPathComponent == record.id else {
                rejected += 1
                continue
            }
            let targetJson = root.appendingPathComponent("protocols").appendingPathComponent(sourceJson.lastPathComponent)
            if FileManager.default.fileExists(atPath: targetJson.path) {
                skipped += 1
                continue
            }
            let stagedPhotos = stage.appendingPathComponent("photos").appendingPathComponent(record.id)
            let stagedInk = stage.appendingPathComponent("signatures").appendingPathComponent(record.id)
            guard validEvidence(record, photos: stagedPhotos, ink: stagedInk) else {
                rejected += 1
                continue
            }
            let targetPhotos = root.appendingPathComponent("photos").appendingPathComponent(record.id)
            let targetInk = root.appendingPathComponent("signatures").appendingPathComponent(record.id)
            if FileManager.default.fileExists(atPath: targetPhotos.path) || FileManager.default.fileExists(atPath: targetInk.path) {
                rejected += 1
                continue
            }
            do {
                try installDirectory(stagedPhotos, to: targetPhotos)
                try installDirectory(stagedInk, to: targetInk)
                try atomicCopy(sourceJson, to: targetJson)
                imported += 1
            } catch {
                try? FileManager.default.removeItem(at: targetJson)
                try? FileManager.default.removeItem(at: targetPhotos)
                try? FileManager.default.removeItem(at: targetInk)
                rejected += 1
            }
        }
        return ArchiveImportResult(imported: imported, skippedExisting: skipped, rejected: rejected)
    }

    private static func validEvidence(_ record: HandoverProtocol, photos: URL, ink: URL) -> Bool {
        let referencedNames = record.defects.flatMap { $0.photoFiles() } + record.objects.flatMap { $0.photoFiles() } +
            record.signatures.map(\.file).filter { !$0.isBlank }
        if referencedNames.contains(where: { !EvidenceNames.isArchiveSafe($0) }) { return false }
        if !ProtocolIntegrity.missingEvidence(record, photoDir: photos, signatureDir: ink).isEmpty { return false }
        if record.isFinalized(), !ProtocolIntegrity.matches(record, photoDir: photos, signatureDir: ink) { return false }
        let described = record.defects.flatMap(\.photoEvidence) + record.objects.flatMap(\.photoEvidence)
        return described.allSatisfy { evidence in
            evidence.sha256.isBlank ||
                ((try? ProtocolIntegrity.fileHash(photos.appendingPathComponent(evidence.file)))?.caseInsensitiveCompare(evidence.sha256) == .orderedSame)
        }
    }

    private static func installDirectory(_ source: URL, to target: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        guard !FileManager.default.fileExists(atPath: target.path) else { throw ArchiveError.destinationExists }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: target)
    }

    private static func atomicCopy(_ source: URL, to target: URL) throws {
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = target.deletingLastPathComponent().appendingPathComponent("\(target.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.copyItem(at: source, to: tmp)
        try Files.replace(target, with: tmp)
    }

    private static func walk(_ base: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            files.append(url)
        }
        return files
    }

    private static func relativePath(_ url: URL, from base: URL) -> String {
        let basePath = base.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(basePath) ? String(path.dropFirst(basePath.count)) : url.lastPathComponent
    }
}
