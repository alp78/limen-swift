import CoreGraphics
import Foundation
import PDFKit
import UIKit

/// The protocol as an A4 document, drawn with the platform's own PDF context in the app's own
/// style: the Day palette, the panels with their rounded corners and navy border, the system
/// face, every size derived from the screen's tokens. No library and no font file to embed. The
/// pieces live beside this file: the tokens, the paginator, the paints, the blocks, the sheet,
/// the outline, and one file per section.
///
/// The order follows the paper canon the record will be compared against at a conciliation
/// hearing: the parties, the money and meter rubrics this handover actually carries, the rooms
/// with their findings numbered across the record and the charge column explicit, the supplied
/// objects, the record signatures, the deposit release instruction, and the photo annex. A cover
/// opens it with the facts a reader wants first and the contents.
///
/// The paper prints what was recorded and nothing else. Undamaged surfaces do not appear, because
/// a page of "in order" lines beside three real findings buries the three; and a dossier rubric
/// nobody filled in does not appear either, because an empty field on a signed document reads as
/// an unanswered question. Records written before this, which do carry an exhaustive item grid,
/// still print theirs: those grades are part of what the parties put their names to.
///
/// The language of the document is the `Str` handed in, independent of the UI language: a
/// Lausanne regie hands a German-speaking tenant a French protocol or the reverse, and the choice
/// belongs to the moment of export.
///
/// Every measurement is in the Android sheet's own units, a 1240 by 1754 page, and the context is
/// scaled so that sheet fills an A4 leaf: the same proportions to a tenth of a percent, so a print
/// at 100 percent is the size it was meant to be.
public enum PdfExport {
    public enum ExportError: Error, Equatable {
        case notFinalized
        case integrityMismatch
        case rendering
        /// The sections drawn were not the sections planned, or the drawing pass broke its pages
        /// elsewhere than the counting pass: the contents would name a wrong page under a signed
        /// document, so the document is refused rather than handed over.
        case contentsMismatch
    }

    static let a4 = CGSize(width: 595.276, height: 841.89)

    public static func export(_ p: HandoverProtocol, _ s: Str, photoDir: URL, signatureDir: URL, folder: URL = Exports.folder, now: Date = Date()) throws -> ExportedFile {
        guard p.isFinalized() else { throw ExportError.notFinalized }
        guard ProtocolIntegrity.matches(p, photoDir: photoDir, signatureDir: signatureDir) else { throw ExportError.integrityMismatch }
        let rendered = try document(p, s, photoDir: photoDir, signatureDir: signatureDir)
        defer { rendered.discard() }
        let kind = p.kind == .entry ? s.entry : s.exit
        let name = "limen-\(kind.lowercased().replacingOccurrences(of: " ", with: "-"))-\(Exports.stamp(now)).pdf"
        return try Exports.write(name: name, in: folder) { url in try FileManager.default.copyItem(at: rendered.pdf, to: url) }
    }

    /// The document, rendered into two scratch files the caller moves or copies into place and
    /// then discards. Files rather than bytes, because a record holds any number of photographs
    /// and the PDF and its HTML copy are mostly those photographs.
    public struct Document: Sendable {
        public let pdf: URL
        public let html: URL
        public let pages: Int

        public init(pdf: URL, html: URL, pages: Int) {
            self.pdf = pdf
            self.html = html
            self.pages = pages
        }

        /// Removes the scratch files once they have been copied where they belong.
        public func discard() {
            try? FileManager.default.removeItem(at: pdf)
            try? FileManager.default.removeItem(at: html)
        }
    }

    /// Twice: the first pass only counts the sheets so the second can number them "3 / 7". A form
    /// that names its own total is a form nobody can quietly take a page out of, which is the
    /// tamper evidence paper has always used and people actually check. The counting pass also
    /// learns the page each section opens on, for the contents and the room panels' pointers into
    /// the annex; it draws no photograph and writes no HTML, and reads each photograph's size from
    /// its header, so both passes break the pages in the same places. After each pass the sections
    /// that opened are checked against the plan, and after the second against the first.
    public static func document(_ p: HandoverProtocol, _ s: Str, photoDir: URL, signatureDir: URL, scratch: URL = AppFiles.scratch) throws -> Document {
        try EvidenceValidation.requireReadable(p, photoDir: photoDir, signatureDir: signatureDir)
        let reference = p.isFinalized() ? reference(p) : s.previewDraft
        let planned = Outline.plan(p, s)
        let logo = logo()
        let counted = try build(p, s, photoDir: photoDir, signatureDir: signatureDir, reference: reference, planned: planned,
                                total: 0, output: .memory, pages: nil, annexPages: [:], logo: logo)
        guard counted.marks.map({ Outline.Entry($0.title, $0.level) }) == planned else { throw ExportError.contentsMismatch }
        let pages = counted.marks.map(\.page)
        let annexPages = Dictionary(counted.marks.compactMap { mark in mark.key.map { ($0, mark.page) } }, uniquingKeysWith: { first, _ in first })
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let stem = scratch.appendingPathComponent("render-\(UUID().uuidString)")
        let pdfURL = stem.appendingPathExtension("pdf")
        let htmlURL = stem.appendingPathExtension("html")
        let spool = stem.appendingPathExtension("plates")
        // The plate JPEGs are needed until the PDF is closed, and never afterwards.
        defer { try? FileManager.default.removeItem(at: spool) }
        let drawn: RenderPass
        do {
            drawn = try build(p, s, photoDir: photoDir, signatureDir: signatureDir, reference: reference, planned: planned, total: counted.pages,
                              output: .files(pdf: pdfURL, html: htmlURL, spool: spool), pages: pages, annexPages: annexPages, logo: logo)
        } catch {
            try? FileManager.default.removeItem(at: pdfURL)
            try? FileManager.default.removeItem(at: htmlURL)
            throw error
        }
        guard drawn.marks == counted.marks else {
            try? FileManager.default.removeItem(at: pdfURL)
            try? FileManager.default.removeItem(at: htmlURL)
            throw ExportError.contentsMismatch
        }
        // The page-count check reads the written file back, as the two passes have to agree and
        // the reader that will open it has to agree with both.
        guard drawn.pages == counted.pages, let pdf = PDFDocument(url: pdfURL),
              pdf.pageCount == drawn.pages, pdf.pageCount > 0, !(pdf.string ?? "").isEmpty else {
            try? FileManager.default.removeItem(at: pdfURL)
            try? FileManager.default.removeItem(at: htmlURL)
            throw ExportError.rendering
        }
        return Document(pdf: pdfURL, html: htmlURL, pages: drawn.pages)
    }

    /// One rendering pass. `total` is 0 while counting and the real page count afterwards;
    /// `pages` and `annexPages` are what the counting pass learned, nil and empty before it.
    private static func build(_ p: HandoverProtocol, _ s: Str, photoDir: URL, signatureDir: URL, reference: String, planned: [Outline.Entry],
                              total: Int, output: Output, pages: [Int]?, annexPages: [String: Int], logo: CGImage?) throws -> RenderPass {
        let kind = p.kind == .entry ? s.entry : s.exit
        let address = [p.address, p.place].filter { !$0.isBlank }.joined(separator: ", ")
        let sheet = try Sheet(s: s, reference: reference, kindLine: "\(s.protocolKind): \(kind)", addressLine: address, total: total,
                              output: output, logo: logo, annexPages: annexPages)
        let cards = p.dossierCards()
        sheet.cover(p, planned: planned, pages: pages)
        if Outline.legalOverlay(p) { sheet.legalOverlay(p) }
        if Outline.controller(p) { sheet.dataController(p) }
        if cards.contains(.contract) { sheet.contract(p) }
        if cards.contains(.deposit) { sheet.deposit(p) }
        if Outline.meters(p) { sheet.meters(p) }
        if cards.contains(.keys) { sheet.keys(p) }
        sheet.rooms(p)
        sheet.objects(p)
        sheet.strayFindings(p)
        sheet.extras(p)
        sheet.remarks(p)
        sheet.signatures(p, signatureDir)
        sheet.delivery(p)
        sheet.release(p)
        sheet.annex(p, photoDir, measuring: total == 0)
        return try sheet.close()
    }

    /// The seal, decoded once per pass and drawn on every page from the same image, which the
    /// PDF context then embeds once. The same resource as the launcher and the header, so the
    /// three can never drift apart. Decoded at half size: the 512-pixel mark prints 22 mm wide on
    /// the cover, where 256 pixels are 300 dpi, and at full size it was 374 KB of a 500 KB
    /// two-page record on Android.
    private static func logo() -> CGImage? {
        guard let url = Bundle.limenKit.url(forResource: "limen_mark", withExtension: "png") else { return nil }
        return PhotoDecode.sampled(url, targetWidth: 256)
    }

    /// The filing reference is a readable prefix of the frozen evidence fingerprint.
    static func reference(_ p: HandoverProtocol) -> String { "LIMEN-\(p.evidenceFingerprint.prefix(16))" }
}

extension HandoverProtocol {
    /// The item a finding names, or nil when it is about the room or the object as a whole.
    ///
    /// A finding written by this version carries its own label. Older records kept it on the
    /// room's item row instead, so those are still resolved through the row.
    public func defectItemLabel(_ d: Defect, _ s: Str) -> String? {
        guard let key = d.item else { return nil }
        if key == .custom {
            if !d.itemLabel.isBlank { return d.itemLabel }
            let legacy = rooms.first { $0.id == d.roomId }?.items.first {
                $0.key == key && (d.itemId.isBlank || $0.itemId.isBlank || d.itemId == $0.itemId)
            }
            if let label = legacy?.label, !label.isBlank { return label }
            return s.item(key)
        }
        return s.item(key)
    }

    /// Where a finding hangs: a room of the flat, or a supplied object.
    public func defectPlace(_ d: Defect, _ s: Str) -> String {
        if !d.objectId.isBlank {
            return objects.first { $0.id == d.objectId }?.displayName(s) ?? s.objects
        }
        guard let room = rooms.first(where: { $0.id == d.roomId }) else { return "" }
        return room.name.ifBlank(s.room(room.kind))
    }
}

extension ObjectEntry {
    /// What an object row is called: its catalogue entry when it has one, else what was typed.
    public func displayName(_ s: Str) -> String {
        switch group {
        case .appliance: return Appliance(rawValue: catalogue).map(s.appliance) ?? label
        case .furniture: return Furniture(rawValue: catalogue).map(s.furniture) ?? label
        case .other: return label
        }
    }
}
