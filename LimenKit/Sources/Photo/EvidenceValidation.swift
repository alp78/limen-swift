import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Decoding is a separate boundary from hashing: historical fingerprints may cover any bytes,
/// but a finalized or delivered document must actually display every referenced image.
public enum EvidenceValidation {
    public static let maxIntakeBytes: Int64 = 32 * 1024 * 1024
    public struct UnrenderableEvidence: Error, LocalizedError, Equatable {
        public let files: [String]
        public var errorDescription: String? { "Evidence cannot be read: " + files.joined(separator: ", ") }
        public init(files: [String]) { self.files = files }
    }

    @discardableResult
    public static func validatePhoto(_ file: URL) throws -> String {
        guard Files.isRegularFile(file), (1...maxIntakeBytes).contains(Files.size(file)),
              PhotoDecode.readable(file), let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let identifier = CGImageSourceGetType(source), let type = UTType(identifier as String),
              let mime = type.preferredMIMEType else { throw UnrenderableEvidence(files: [file.lastPathComponent]) }
        return mime
    }

    @discardableResult
    public static func validateDocument(_ file: URL) throws -> String {
        guard Files.isRegularFile(file), (1...maxIntakeBytes).contains(Files.size(file)) else {
            throw UnrenderableEvidence(files: [file.lastPathComponent])
        }
        if readablePDF(file) { return "application/pdf" }
        return try validatePhoto(file)
    }

    public static func requireReadable(_ record: HandoverProtocol, photoDir: URL, signatureDir: URL) throws {
        let failures = unreadable(record, photoDir: photoDir, signatureDir: signatureDir)
        if !failures.isEmpty { throw UnrenderableEvidence(files: failures) }
    }

    public static func unreadable(_ record: HandoverProtocol, photoDir: URL, signatureDir: URL) -> [String] {
        var failures: [String] = []
        for name in record.allPhotoFiles() {
            if !EvidenceNames.isArchiveSafe(name) || !PhotoDecode.readable(photoDir.appendingPathComponent(name)) { failures.append(name) }
        }
        for signature in record.signatures where !signature.file.isBlank {
            if !EvidenceNames.isArchiveSafe(signature.file) || !PhotoDecode.readable(signatureDir.appendingPathComponent(signature.file)) {
                failures.append(signature.file)
            }
        }
        for evidence in record.allPhotoEvidence() where !evidence.sha256.isBlank {
            if !hashMatches(photoDir.appendingPathComponent(evidence.file), evidence.sha256) { failures.append(evidence.file) }
        }
        for document in record.details.attachments where !document.file.isBlank {
            let file = photoDir.appendingPathComponent(document.file)
            let readable = document.mime == "application/pdf" ? readablePDF(file) : document.mime.hasPrefix("image/") && PhotoDecode.readable(file)
            if !EvidenceNames.isArchiveSafe(document.file) || !readable || !hashMatches(file, document.sha256) ||
                (document.bytes > 0 && Files.size(file) != document.bytes) { failures.append(document.file) }
        }
        return failures.distinct()
    }

    static func hashMatches(_ file: URL, _ expected: String) -> Bool {
        guard expected.count == 64, expected.allSatisfy({ $0.isHexDigit }),
              let hash = try? ProtocolIntegrity.fileHash(file) else { return false }
        return hash.caseInsensitiveCompare(expected) == .orderedSame
    }

    private static func readablePDF(_ file: URL) -> Bool {
        guard Files.isRegularFile(file), let pdf = CGPDFDocument(file as CFURL), !pdf.isEncrypted,
              (1...1_000).contains(pdf.numberOfPages),
              let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        for index in 1...pdf.numberOfPages {
            guard let page = pdf.page(at: index) else { return false }
            let box = page.getBoxRect(.mediaBox)
            guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0 else { return false }
            context.saveGState()
            context.concatenate(page.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: 64, height: 64), rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            context.restoreGState()
        }
        return true
    }
}
