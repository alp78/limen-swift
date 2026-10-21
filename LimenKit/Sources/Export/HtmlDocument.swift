import Foundation

/// Built by the PDF's own drawing pass: identical content selection and reading order, in the
/// app's colours and shapes, so the accessible copy and the screen's preview look like the paper
/// and the screen at once. Entered text is always escaped, images are embedded, and the companion
/// has no executable content.
///
/// Written straight to its file as the pages are drawn and never held whole: built in memory, a
/// record of thirty photographs is tens of megabytes of base64, and a record holds any number of
/// photographs. The counting pass has no sink at all.
final class HtmlSink {
    private let handle: FileHandle

    init(url: URL, language: Lang, title: String) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        put("<!doctype html><html lang=\"\(language.rawValue.lowercased())\"><head><meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            + "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'\">"
            + "<title>\(HtmlDocument.escape(title))</title><style>\(Self.style)</style></head><body><main>")
    }

    func put(_ text: String) {
        handle.write(Data(text.utf8))
    }

    private func id(_ anchor: String?) -> String { anchor.map { " id=\"\(HtmlDocument.escape($0))\"" } ?? "" }

    /// The cover's banner: the name, then one line each for what the record is and where.
    func banner(_ name: String, _ lines: [String]) {
        put("<header class=\"banner\"><h1>\(HtmlDocument.escape(name))</h1>")
        for line in lines where !line.isBlank { put("<p>\(HtmlDocument.escape(line))</p>") }
        put("</header>")
    }

    func heading(_ text: String, anchor: String? = nil) { put("<h2\(id(anchor))>\(HtmlDocument.escape(text))</h2>") }

    func text(_ text: String) { put("<p>\(HtmlDocument.escape(text))</p>") }

    func fields(_ pairs: [(String, String)]) {
        put("<dl class=\"grid\">")
        for (name, value) in pairs { put("<div><dt>\(HtmlDocument.escape(name))</dt><dd>\(HtmlDocument.escape(value.ifBlank("–")))</dd></div>") }
        put("</dl>")
    }

    /// A panel: its title with its pill, then whatever `body` writes.
    func panel(_ title: String, tone: String, pill: String?, pillTone: String?, anchor: String?, _ body: () -> Void) {
        let pillHtml = pill.map { "<span class=\"pill \(HtmlDocument.escape(pillTone ?? ""))\">\(HtmlDocument.escape($0))</span>" } ?? ""
        put("<section class=\"panel \(HtmlDocument.escape(tone))\"\(id(anchor))><h2>\(HtmlDocument.escape(title))\(pillHtml)</h2>")
        body()
        put("</section>")
    }

    func chips(_ items: [(String, Bool)]) {
        put("<ul class=\"chips\">")
        for (text, active) in items { put("<li class=\"chip\(active ? " active" : "")\">\(HtmlDocument.escape(text))</li>") }
        put("</ul>")
    }

    func finding(_ number: Int, _ where: String, _ body: () -> Void) {
        put("<article class=\"finding\"><p class=\"where\"><span class=\"badge\">\(number)</span>\(HtmlDocument.escape(`where`))</p>")
        body()
        put("</article>")
    }

    struct ContentsEntry {
        let title: String
        let level: Int
        let detail: String?
        let anchor: String?
    }

    func contents(_ entries: [ContentsEntry]) {
        put("<nav class=\"contents\"><ul>")
        for entry in entries {
            let title = entry.anchor.map { "<a href=\"#\(HtmlDocument.escape($0))\">\(HtmlDocument.escape(entry.title))</a>" } ?? HtmlDocument.escape(entry.title)
            let detail = entry.detail.map { " <small>\(HtmlDocument.escape($0))</small>" } ?? ""
            put("<li class=\"l\(entry.level)\">\(title)\(detail)</li>")
        }
        put("</ul></nav>")
    }

    func list(_ items: [String]) {
        put("<ul class=\"meta\">")
        for item in items where !item.isBlank { put("<li>\(HtmlDocument.escape(item))</li>") }
        put("</ul>")
    }

    /// A signature, which carries transparency and so goes as PNG.
    func image(png: Data, alt: String) {
        figure(type: "png", bytes: png, alt: alt, captionHtml: "<p>\(HtmlDocument.escape(alt))</p>")
    }

    /// An annex plate in the exported copy: the very JPEG the PDF carries, with its legend.
    func plate(_ jpeg: URL, _ card: AnnexContent.Card) throws {
        figure(type: "jpeg", bytes: try Data(contentsOf: jpeg, options: .mappedIfSafe), alt: Self.alt(card), captionHtml: Self.legend(card))
    }

    static func alt(_ card: AnnexContent.Card) -> String { "\(card.where), \(title(card))" }

    private static func title(_ card: AnnexContent.Card) -> String {
        card.number.map { "\($0). \(card.title)" } ?? card.title
    }

    /// The legend as a paragraph and a list: the metadata one item each, never joined with a dot.
    static func legend(_ card: AnnexContent.Card) -> String {
        var html = "<p><small>\(HtmlDocument.escape(card.where))</small><br><strong>\(HtmlDocument.escape(title(card)))</strong>"
        for line in card.context { html += "<br>\(HtmlDocument.escape(line))" }
        html += "</p><ul class=\"meta\">"
        for line in card.meta { html += "<li>\(HtmlDocument.escape(line))</li>" }
        html += "</ul>"
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

    /// The Day palette's hex values, the same ones the page is drawn in: Android's stylesheet
    /// with the iPhone's face first in the stack and without the measure cap on `main`, which the
    /// house rule forbids on text. The preview's Content Security Policy allows exactly this inline sheet.
    static let style =
        "body{font-family:-apple-system,system-ui,Roboto,'Segoe UI',sans-serif;color:#1A1D23;background:#F6F7F9;line-height:1.5;margin:0;padding:1rem;overflow-wrap:anywhere}"
        + ".banner{background:#233350;color:#fff;border-radius:14px;padding:1.5rem;margin-bottom:1rem}.banner h1{margin:0 0 .5rem;letter-spacing:-.02em}.banner p{margin:.2rem 0;color:#E5E7EA}"
        + "h2{font-size:1.3rem;border-bottom:1.5px solid #233350;padding-bottom:.3rem;margin:1.5rem 0 .8rem}"
        + "h3{font-size:1.1rem;border-bottom:1.5px solid #233350;padding-bottom:.3rem;margin:1.5rem 0 .8rem}"
        + ".panel{background:#E7E9EE;border:1.5px solid #233350;border-radius:12px;padding:1rem;margin:.7rem 0}.panel.warning{background:#FCEBD2;border-color:#835000}"
        + ".panel>h2{font-size:.75rem;font-weight:500;letter-spacing:.02em;text-transform:uppercase;color:#5B6472;border:0;padding:0;margin:0 0 .6rem;display:flex;justify-content:space-between;align-items:center;gap:.5rem}"
        + ".pill{font-size:.75rem;font-weight:700;border-radius:6px;padding:.15rem .6rem;text-transform:uppercase;white-space:nowrap}.pill.seal{background:#233350;color:#fff}.pill.warning{background:#FCEBD2;color:#835000;border:1.5px solid #835000}.pill.dim{background:#EFF1F4;color:#5B6472}.pill.paper{background:#fff;color:#233350}"
        + "dl.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(12rem,1fr));gap:.6rem;margin:.4rem 0}dt{font-size:.75rem;font-weight:500;color:#5B6472}dd{margin:0}"
        + ".chips{list-style:none;display:flex;flex-wrap:wrap;gap:.4rem;padding:0;margin:.4rem 0}.chip{background:#EFF1F4;border:1px solid #D7DAE0;border-radius:10px;padding:.15rem .6rem;font-size:.8rem}.chip.active{background:#233350;color:#fff;border-color:#233350}"
        + ".finding{margin:.8rem 0;padding-left:2.6rem;position:relative}.finding .where{font-size:.75rem;text-transform:uppercase;color:#5B6472;margin:0 0 .2rem}.badge{position:absolute;left:0;top:0;min-width:1.4rem;padding:0 .3rem;background:#233350;color:#fff;border-radius:8px;text-align:center;font-weight:700;font-size:.85rem;line-height:1.5rem}"
        + "figure{background:#E7E9EE;border:1.5px solid #233350;border-radius:12px;padding:1rem;margin:1rem 0}img{border-radius:8px;border:1.5px solid #233350;max-width:100%;height:auto;display:block;box-sizing:border-box}figcaption{margin-top:.6rem}figcaption small,ul.meta{color:#5B6472;font-size:.85rem}ul.meta{padding-left:1.2rem;margin:.3rem 0}"
        + "nav.contents ul{list-style:none;padding:0;margin:0}nav.contents li{margin:.15rem 0}nav.contents li.l1{padding-left:1.4rem;color:#5B6472;font-size:.9rem}nav.contents a{color:#233350}"
        + "p{white-space:pre-wrap;margin:.3rem 0}"
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
