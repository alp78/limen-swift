import Foundation

/// The same drawing pass emits semantic blocks before wrapping them onto PDF pages. Entered
/// text is always escaped, images are embedded, and the companion has no executable content.
enum HtmlDocument {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func wrap(_ body: String, language: Lang, title: String) -> String {
        """
        <!doctype html><html lang="\(language.rawValue.lowercased())"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'">
        <title>\(escape(title))</title><style>
        body{font:1.1rem/1.6 system-ui,sans-serif;color:#111;background:#fff;max-width:52rem;margin:auto;padding:1rem}
        p,dd{white-space:pre-wrap;overflow-wrap:anywhere}h1,h2{line-height:1.3}dt{font-weight:bold}
        dd{margin:0 0 1rem}img{max-width:100%;height:auto}figure{margin:1rem 0}figcaption{overflow-wrap:anywhere}
        @media print{h2{break-after:avoid}figure{break-inside:avoid}}
        </style></head><body><main><h1>\(escape(title))</h1>\(body)</main></body></html>
        """
    }
}

extension PdfExport {
    public static func exportRetained(_ p: HandoverProtocol, _ s: Str, store: Store, now: Date = Date(), publicFolder: URL = Exports.folder) throws -> ExportCopy {
        guard p.isFinalized() else { throw ExportError.notFinalized }
        let photos = store.photoDir(p.id)
        let signatures = store.signatureDir(p.id)
        guard ProtocolIntegrity.matches(p, photoDir: photos, signatureDir: signatures) else { throw ExportError.integrityMismatch }
        let rendered = try document(p, s, photoDir: photos, signatureDir: signatures)
        let property = String((p.address + "-" + p.place).unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : "-"
        }.joined().prefix(70))
        let reference = String(p.evidenceFingerprint.prefix(12))
        let name = "Limen-\(property)-\(s.lang.rawValue.lowercased())-\(reference)-d\(p.deliveryRevision)-\(Exports.stamp(now))-\(UUID().uuidString.prefix(8))"
        let directory = store.root.appendingPathComponent("exports").appendingPathComponent(p.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pdf = try Exports.write(name: name + ".pdf", in: directory) { try rendered.pdf.write(to: $0) }
        let html: ExportedFile
        do {
            html = try Exports.write(name: name + ".html", in: directory) { try rendered.html.write(to: $0) }
        } catch {
            try? FileManager.default.removeItem(at: pdf.url)
            throw error
        }
        // Logical paths travel between devices. Public copies are conveniences; history always
        // resolves the private retained pair and verifies the PDF hash before offering it.
        let hash = try ProtocolIntegrity.fileHash(pdf.url)
        let publicPdf = try Exports.write(name: pdf.displayName, in: publicFolder) { try rendered.pdf.write(to: $0) }
        do { _ = try Exports.write(name: html.displayName, in: publicFolder) { try rendered.html.write(to: $0) } } catch {
            try? FileManager.default.removeItem(at: publicPdf.url)
            throw error
        }
        return ExportCopy(uri: "exports/\(p.id)/\(pdf.displayName)", name: pdf.displayName, bytes: pdf.bytes,
                          language: s.lang.rawValue, deliveryRevision: p.deliveryRevision,
                          epochMs: Int64(now.timeIntervalSince1970 * 1000),
                          companionUri: "exports/\(p.id)/\(html.displayName)", sha256: hash)
    }
}
