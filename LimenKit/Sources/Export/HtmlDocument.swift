import Foundation

/// The same drawing pass emits semantic blocks before wrapping them onto PDF pages. Entered
/// text is always escaped, images are embedded, and the companion has no executable content.
///
/// Written straight to its file as the pages are drawn and never held whole: built in memory, a
/// record of thirty photographs is tens of megabytes of base64, and a record holds any number of
/// photographs. The counting pass has no sink at all.
final class HtmlSink {
    private let handle: FileHandle

    init(url: URL, language: Lang, title: String) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        put("""
        <!doctype html><html lang="\(language.rawValue.lowercased())"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <title>\(HtmlDocument.escape(title))</title><style>
        body{font:1.1rem/1.6 system-ui,sans-serif;color:#111;background:#fff;max-width:52rem;margin:auto;padding:1rem}
        p,dd{white-space:pre-wrap;overflow-wrap:anywhere}h1,h2,h3{line-height:1.3}dt{font-weight:bold}
        h3{border-bottom:2px solid #15202d;padding-top:1.5rem;text-transform:uppercase;letter-spacing:.05em}
        dd{margin:0 0 1rem}img{max-width:100%;height:auto;display:block}
        figure{margin:1rem 0;padding:.75rem;border:1px solid #c8c8c8;border-radius:6px}figcaption{margin-top:.5rem;overflow-wrap:anywhere}figcaption small{color:#555}
        @media print{h2,h3{break-after:avoid}figure{break-inside:avoid}}
        </style></head><body><main><h1>\(HtmlDocument.escape(title))</h1>
        """)
    }

    func put(_ text: String) {
        handle.write(Data(text.utf8))
    }

    func heading(_ text: String) { put("<h2>\(HtmlDocument.escape(text))</h2>") }

    /// A section of the photo annex: a room, the objects, the meters.
    func subheading(_ text: String) { put("<h3>\(HtmlDocument.escape(text))</h3>") }

    func text(_ text: String) { put("<p>\(HtmlDocument.escape(text))</p>") }

    func fields(_ pairs: [(String, String)]) {
        put("<dl>" + pairs.map { "<dt>\(HtmlDocument.escape($0.0))</dt><dd>\(HtmlDocument.escape($0.1))</dd>" }.joined() + "</dl>")
    }

    /// A signature, which carries transparency and so goes as PNG.
    func image(png: Data, alt: String) {
        figure(type: "png", bytes: png, alt: alt, captionHtml: HtmlDocument.escape(alt))
    }

    /// An annex plate in the exported copy: the very JPEG the PDF carries, with its legend.
    func plate(_ jpeg: URL, _ card: AnnexContent.Card) throws {
        figure(type: "jpeg", bytes: try Data(contentsOf: jpeg, options: .mappedIfSafe), alt: Self.alt(card), captionHtml: Self.legend(card))
    }

    static func alt(_ card: AnnexContent.Card) -> String { "\(card.where) · \(title(card))" }

    private static func title(_ card: AnnexContent.Card) -> String {
        card.number.map { "\($0). \(card.title)" } ?? card.title
    }

    static func legend(_ card: AnnexContent.Card) -> String {
        var html = "<small>\(HtmlDocument.escape(card.where))</small><br><strong>\(HtmlDocument.escape(title(card)))</strong>"
        for line in card.context { html += "<br>\(HtmlDocument.escape(line))" }
        html += "<br><small>\(HtmlDocument.escape(card.meta.joined(separator: " · ")))</small>"
        return html
    }

    private func figure(type: String, bytes: Data, alt: String, captionHtml: String) {
        put("<figure><img alt=\"\(HtmlDocument.escape(alt))\" src=\"data:image/\(type);base64,")
        put(bytes.base64EncodedString())
        put("\"><figcaption>\(captionHtml)</figcaption></figure>")
    }

    func finish() throws {
        put("</main></body></html>")
        try handle.close()
    }
}

enum HtmlDocument {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

extension PdfExport {
    /// The retained private copy and its public twin, written from one rendering. The document
    /// is rendered straight into files and moved into place, so a record of any number of
    /// photographs exports without the PDF or the HTML ever sitting whole in memory.
    public static func exportRetained(_ p: HandoverProtocol, _ s: Str, store: Store, now: Date = Date(), publicFolder: URL = Exports.folder) throws -> ExportCopy {
        guard p.isFinalized() else { throw ExportError.notFinalized }
        let photos = store.photoDir(p.id)
        let signatures = store.signatureDir(p.id)
        guard ProtocolIntegrity.matches(p, photoDir: photos, signatureDir: signatures) else { throw ExportError.integrityMismatch }
        let rendered = try document(p, s, photoDir: photos, signatureDir: signatures)
        defer { rendered.discard() }
        let directory = store.root.appendingPathComponent("exports").appendingPathComponent(p.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = Exports.unusedName(Exports.documentName(address: p.address, handoverDate: p.handoverDate, now: now), in: [directory, publicFolder])
        let pdf = try Exports.write(name: name + ".pdf", in: directory) { try FileManager.default.copyItem(at: rendered.pdf, to: $0) }
        let html: ExportedFile
        do {
            html = try Exports.write(name: name + ".html", in: directory) { try FileManager.default.copyItem(at: rendered.html, to: $0) }
        } catch {
            try? FileManager.default.removeItem(at: pdf.url)
            throw error
        }
        // Logical paths travel between devices. Public copies are conveniences; history always
        // resolves the private retained pair and verifies the PDF hash before offering it.
        let hash = try ProtocolIntegrity.fileHash(pdf.url)
        let publicPdf = try Exports.write(name: pdf.displayName, in: publicFolder) { try FileManager.default.copyItem(at: rendered.pdf, to: $0) }
        do { _ = try Exports.write(name: html.displayName, in: publicFolder) { try FileManager.default.copyItem(at: rendered.html, to: $0) } } catch {
            try? FileManager.default.removeItem(at: publicPdf.url)
            throw error
        }
        return ExportCopy(uri: "exports/\(p.id)/\(pdf.displayName)", name: pdf.displayName, bytes: pdf.bytes,
                          language: s.lang.rawValue, deliveryRevision: p.deliveryRevision,
                          epochMs: Int64(now.timeIntervalSince1970 * 1000),
                          companionUri: "exports/\(p.id)/\(html.displayName)", sha256: hash)
    }
}
