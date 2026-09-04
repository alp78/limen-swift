import Foundation

/// What an export produced: where it is, what it is called, how heavy it got.
public struct ExportedFile: Hashable, Sendable {
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
        let target = folder.appendingPathComponent(name)
        let tmp = folder.appendingPathComponent(".\(name).part")
        try? FileManager.default.removeItem(at: tmp)
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
