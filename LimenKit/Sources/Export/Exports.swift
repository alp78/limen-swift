import Foundation

/// What an export produced: where it is, what it is called, how heavy it got.
public struct ExportedFile: Hashable, Sendable, Identifiable {
    public var id: URL { url }
    public let url: URL
    public let displayName: String
    public let bytes: Int64

    public init(url: URL, displayName: String, bytes: Int64) {
        self.url = url
        self.displayName = displayName
        self.bytes = bytes
    }
}

public enum Exports {
    public static func stamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    /// The document's name: the address and the handover's day, dashes between, nothing else.
    /// The fingerprint, the language, the delivery revision and the export time used to follow,
    /// and the owner found the name useless in Files and in a mail; they stay in the record's
    /// export history, where they are read. Letters are folded to ASCII and anything else is a
    /// dash, because the archive's name rule is ASCII and a Pixel restoring the record must take
    /// the file. A record whose handover day is not set yet is named after the day of the export.
    public static func documentName(address: String, handoverDate: String, now: Date) -> String {
        let folded = address.applyingTransform(.stripDiacritics, reverse: false) ?? address
        var slug = folded.unicodeScalars.map { scalar -> String in
            ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) ? String(scalar) : "-"
        }.joined()
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "Limen" }
        let day: String
        if handoverDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            day = handoverDate
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            day = formatter.string(from: now)
        }
        return String(slug.prefix(80)) + "-" + day
    }

    /// `base`, or `base-2`, `base-3` and so on, the first that names no file with any of the
    /// extensions in any of the folders: a second export of a record on the same day keeps the
    /// earlier retained copy, because the history promises every exact copy.
    public static func unusedName(_ base: String, in folders: [URL], extensions: [String] = ["pdf", "html"]) -> String {
        var candidate = base
        var counter = 2
        func taken(_ name: String) -> Bool {
            folders.contains { folder in extensions.contains { FileManager.default.fileExists(atPath: folder.appendingPathComponent(name + "." + $0).path) } }
        }
        while taken(candidate) {
            candidate = "\(base)-\(counter)"
            counter += 1
        }
        return candidate
    }

    /// Documents/Limen, the folder Files shows under On My iPhone: the iOS shape of the
    /// Download/Limen collection the Android app writes into.
    public static var folder: URL {
        let url = AppFiles.documents.appendingPathComponent("Limen")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes into the export folder through a scratch file, so a failure leaves nothing behind
    /// and a reader never sees a half-written document.
    public static func write(name: String, in folder: URL = folder, _ body: (URL) throws -> Void) throws -> ExportedFile {
        guard EvidenceNames.isSafe(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(name)
        let tmp = AppFiles.scratch.appendingPathComponent("export-\(UUID().uuidString).part")
        do {
            try body(tmp)
            try Files.replace(target, with: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
        return ExportedFile(url: target, displayName: name, bytes: Files.size(target))
    }
}
