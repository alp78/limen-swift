import CryptoKit
import Foundation

/// Builds the fingerprint displayed on a finalized record. It covers the canonical protocol data
/// and every original photo and ink file, without claiming to be a qualified signature.
public enum ProtocolIntegrity {
    public enum IntegrityError: Error, Equatable {
        case missingEvidence([String])
        case unreadableFile(String)
    }

    public static func fingerprint(_ protocolRecord: HandoverProtocol, photoDir: URL, signatureDir: URL) throws -> String {
        let evidence = evidenceFiles(protocolRecord, photoDir: photoDir, signatureDir: signatureDir)
        let missing = evidence.filter { !isReadable($0.file) }.map(\.label)
        if !missing.isEmpty { throw IntegrityError.missingEvidence(missing) }
        var digest = SHA256()
        var canonical = protocolRecord
        canonical.evidenceFingerprint = ""
        canonical.deliveryReceipts = []
        canonical.deliveryMetadataEpochMs = 0
        canonical.exportedEpochMs = 0
        digest.update(data: Data(ProtocolJSON.encode(canonical, encodeDefaults: true).compact.utf8))

        // Kotlin's distinctBy keeps the first of each label, and sortedBy compares strings by
        // their UTF-16 units; the labels are ASCII, but the comparison is spelt out so it stays
        // that way if a name ever is not.
        var seen = Set<String>()
        let unique = evidence.filter { seen.insert($0.label).inserted }
            .sorted { $0.label.utf16.lexicographicallyPrecedes($1.label.utf16) }
        for entry in unique {
            digest.update(data: Data(entry.label.utf8))
            digest.update(data: Data(try fileHash(entry.file).utf8))
        }
        return hex(digest.finalize())
    }

    public static func matches(_ protocolRecord: HandoverProtocol, photoDir: URL, signatureDir: URL) -> Bool {
        guard protocolRecord.isFinalized() else { return false }
        guard let computed = try? fingerprint(protocolRecord, photoDir: photoDir, signatureDir: signatureDir) else { return false }
        return protocolRecord.evidenceFingerprint == computed
    }

    public static func missingEvidence(_ protocolRecord: HandoverProtocol, photoDir: URL, signatureDir: URL) -> [String] {
        evidenceFiles(protocolRecord, photoDir: photoDir, signatureDir: signatureDir)
            .filter { !isReadable($0.file) }
            .map(\.label)
    }

    /// The SHA-256 of a file, upper case hex, streamed so a twelve-megapixel photograph never sits
    /// whole in memory.
    public static func fileHash(_ file: URL) throws -> String {
        guard isReadable(file), let handle = try? FileHandle(forReadingFrom: file) else {
            throw IntegrityError.unreadableFile(file.lastPathComponent)
        }
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            digest.update(data: chunk)
        }
        return hex(digest.finalize())
    }

    /// Upper case, locale free: the same bytes read the same string on every handset.
    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02X", $0) }.joined()
    }

    static func isReadable(_ file: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: file.path),
              let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? NSNumber else { return false }
        return size.int64Value > 0
    }

    private static func evidenceFiles(_ p: HandoverProtocol, photoDir: URL, signatureDir: URL) -> [(label: String, file: URL)] {
        var files: [(label: String, file: URL)] = []
        for defect in p.defects {
            for name in defect.photoFiles() { files.append(("photo/\(name)", resolvedFile(photoDir, name))) }
        }
        for entry in p.objects {
            for name in entry.photoFiles() { files.append(("photo/\(name)", resolvedFile(photoDir, name))) }
        }
        for signature in p.signatures where !signature.file.isBlank {
            files.append(("ink/\(signature.file)", resolvedFile(signatureDir, signature.file)))
        }
        return files
    }

    /// Invalid names resolve to a guaranteed-missing child, never outside the evidence root.
    private static func resolvedFile(_ root: URL, _ name: String) -> URL {
        if EvidenceNames.isSafe(name) {
            return root.appendingPathComponent(name)
        }
        return root.appendingPathComponent(".invalid-evidence").appendingPathComponent(String(name.hashValue))
    }
}

/// The two checks a file name has to pass before the record may point at it.
public enum EvidenceNames {
    /// Java's `name == File(name).name`: no path separator anywhere, and not a dot entry.
    public static func isSafe(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && name != "." && name != ".."
    }

    /// The archive's stricter rule: one segment of ordinary characters, at most 200 of them.
    public static func isArchiveSafe(_ segment: String) -> Bool {
        guard (1...200).contains(segment.count), segment != ".", segment != ".." else { return false }
        return segment.unicodeScalars.allSatisfy { scalar in
            ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "." || scalar == "_" || scalar == "-"
        }
    }
}
