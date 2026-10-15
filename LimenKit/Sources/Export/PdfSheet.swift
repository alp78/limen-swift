import CoreGraphics
import Foundation
import UIKit

extension PdfExport {
    struct RenderPass {
        let data: Data
        let pages: Int
        let html: String
    }

    // MARK: The sheet: cursor, page breaks, footer

    /// A face at a size, the Paint of the Android sheet: sans or mono, regular or bold, in ink or grey.
    struct Ink {
        let font: UIFont
        let colour: UIColor
        var size: CGFloat { font.pointSize }

        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }

        var attributes: [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: colour] }
    }

    final class Sheet {
        let s: Str
        let reference: String
        let total: Int
        private let data = NSMutableData()
        private var consumer: CGDataConsumer?
        private var pdf: CGContext?
        var y: CGFloat = 0
        var pageNo = 0
        private var pageOpen = false
        var html: [String] = []
        var suppressHTML = false
        var renderingFailed = false

        let black = UIColor.black
        let grey = UIColor(red: 90 / 255, green: 90 / 255, blue: 90 / 255, alpha: 1)
        let titleInk: Ink
        let section: Ink
        let label: Ink
        let value: Ink
        let body: Ink
        let small: Ink
        let ruleColour = UIColor(red: 200 / 255, green: 200 / 255, blue: 200 / 255, alpha: 1)

        init(s: Str, reference: String, total: Int) throws {
            self.s = s
            self.reference = reference
            self.total = total
            titleInk = Ink(font: .monospacedSystemFont(ofSize: 40, weight: .bold), colour: black)
            section = Ink(font: .systemFont(ofSize: 26, weight: .bold), colour: black)
            label = Ink(font: .systemFont(ofSize: 23), colour: grey)
            value = Ink(font: .monospacedSystemFont(ofSize: 26, weight: .regular), colour: black)
            body = Ink(font: .systemFont(ofSize: 26), colour: black)
            small = Ink(font: .systemFont(ofSize: 22), colour: grey)
            guard let consumer = CGDataConsumer(data: data), let pdf = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw ExportError.rendering }
            self.consumer = consumer
            self.pdf = pdf
        }

        func newPage() {
            finish()
            pageNo += 1
            guard let pdf else { return }
            var box = CGRect(origin: .zero, size: a4)
            pdf.beginPage(mediaBox: &box)
            // PDF space runs upward from the bottom left; the sheet is drawn top down in its own
            // units, so the page is flipped and scaled once here and every drawing call below
            // reads exactly like the Android one.
            pdf.translateBy(x: 0, y: a4.height)
            pdf.scaleBy(x: a4.width / pageWidth, y: -a4.height / pageHeight)
            pdf.setFillColor(UIColor.white.cgColor)
            pdf.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
            pageOpen = true
            y = margin
        }

        func finish() {
            guard pageOpen, let pdf else { return }
            let wasSuppressed = suppressHTML
            suppressHTML = true
            defer { suppressHTML = wasSuppressed }
            // The footer: the instrument's name and the page, quietly.
            line(margin, pageHeight - foot - 14, pageWidth - margin, pageHeight - foot - 14, ruleColour, 1.5)
            text("Limen · \(reference)", margin, pageHeight - foot + 8, small)
            let pageText = total > 0 ? "\(s.pdfPage) \(pageNo) / \(total)" : "\(s.pdfPage) \(pageNo)"
            text(pageText, pageWidth - margin - small.width(pageText), pageHeight - foot + 8, small)
            pdf.endPage()
            pageOpen = false
        }

        func close() throws -> RenderPass {
            finish()
            pdf?.closePDF()
            guard !renderingFailed, pdf != nil else { throw ExportError.rendering }
            return RenderPass(data: data as Data, pages: pageNo, html: HtmlDocument.wrap(html.joined(separator: "\n"), language: s.lang, title: reference))
        }

        /// Guarantees `need` vertical units, breaking the page when they are not there.
        func ensure(_ need: CGFloat) {
            if !pageOpen || y + need > pageHeight - foot - 30 { newPage() }
        }

        func gap(_ v: CGFloat) { y += v }

        /// Draws with the baseline at `baseline`, the way Canvas.drawText places its text.
        func text(_ string: String, _ x: CGFloat, _ baseline: CGFloat, _ ink: Ink) {
            if !suppressHTML { html.append("<p>\(HtmlDocument.escape(string))</p>") }
            guard let pdf else { renderingFailed = true; return }
            UIGraphicsPushContext(pdf)
            // NSString's UIKit drawing expects the top-down context established by newPage.
            // A second local flip makes every glyph upside down while text extraction still passes.
            (string as NSString).draw(at: CGPoint(x: x, y: baseline - ink.font.ascender), withAttributes: ink.attributes)
            UIGraphicsPopContext()
        }

        func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ colour: UIColor, _ width: CGFloat) {
            guard let pdf else { return }
            pdf.setStrokeColor(colour.cgColor)
            pdf.setLineWidth(width)
            pdf.move(to: CGPoint(x: x1, y: y1))
            pdf.addLine(to: CGPoint(x: x2, y: y2))
            pdf.strokePath()
        }

        func image(_ image: CGImage, in rect: CGRect, alt: String = "") {
            if !suppressHTML, !alt.isEmpty, let png = UIImage(cgImage: image).pngData() {
                html.append("<figure><img alt=\"\(HtmlDocument.escape(alt))\" src=\"data:image/png;base64,\(png.base64EncodedString())\"><figcaption>\(HtmlDocument.escape(alt))</figcaption></figure>")
            }
            guard let pdf else { return }
            pdf.saveGState()
            pdf.translateBy(x: rect.minX, y: rect.maxY)
            pdf.scaleBy(x: 1, y: -1)
            pdf.interpolationQuality = .high
            pdf.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
            pdf.restoreGState()
        }

        func sectionTitle(_ title: String) {
            html.append("<h2>\(HtmlDocument.escape(title))</h2>")
            let wasSuppressed = suppressHTML
            suppressHTML = true
            defer { suppressHTML = wasSuppressed }
            ensure(60)
            gap(16)
            text(title.uppercased(), margin, y + section.size, section)
            y += section.size + 8
            line(margin, y, pageWidth - margin, y, ruleColour, 1.5)
            gap(10)
        }

        func labeledRow(_ pairs: [(String, String)]) {
            html.append("<dl>" + pairs.map { "<dt>\(HtmlDocument.escape($0.0))</dt><dd>\(HtmlDocument.escape($0.1))</dd>" }.joined() + "</dl>")
            let wasSuppressed = suppressHTML
            suppressHTML = true
            defer { suppressHTML = wasSuppressed }
            let width = (pageWidth - 2 * margin) / CGFloat(pairs.count)
            let columns = pairs.map { heading, entry in
                (wrapLines(heading, label, width - 18), wrapLines(entry.ifBlank("–"), value, width - 18))
            }
            let labelLines = columns.map { $0.0.count }.max() ?? 0
            let valueLines = columns.map { $0.1.count }.max() ?? 0
            let labelStep = label.size + 5
            let valueStep = value.size + 6
            let need = CGFloat(labelLines) * labelStep + CGFloat(valueLines) * valueStep + 14
            if need > pageHeight - margin - foot - 30 {
                for (heading, entry) in pairs {
                    wrapped(heading, label)
                    wrapped(entry, value)
                    gap(10)
                }
                return
            }
            ensure(need)
            for (index, column) in columns.enumerated() {
                let x = margin + CGFloat(index) * width
                for (line, string) in column.0.enumerated() {
                    text(string, x, y + label.size + CGFloat(line) * labelStep, label)
                }
                let valueTop = y + CGFloat(labelLines) * labelStep
                for (line, string) in column.1.enumerated() {
                    text(string, x, valueTop + value.size + CGFloat(line) * valueStep, value)
                }
            }
            y += need
        }

        func wrapped(_ string: String, _ ink: Ink, x: CGFloat = margin, width: CGFloat = pageWidth - 2 * margin) {
            if !suppressHTML { html.append("<p>\(HtmlDocument.escape(string))</p>") }
            let wasSuppressed = suppressHTML
            suppressHTML = true
            defer { suppressHTML = wasSuppressed }
            for line in wrapLines(string, ink, width) {
                ensure(ink.size + 10)
                text(line, x, y + ink.size, ink)
                y += ink.size + 7
            }
        }

        func ellipsize(_ string: String, _ ink: Ink, _ width: CGFloat) -> String {
            if ink.width(string) <= width { return string }
            var t = string
            while !t.isEmpty, ink.width("\(t)…") > width { t.removeLast() }
            return "\(t)…"
        }

        func wrapLines(_ string: String, _ ink: Ink, _ width: CGFloat) -> [String] {
            var out: [String] = []
            for paragraph in string.split(separator: "\n", omittingEmptySubsequences: false) {
                var line = ""
                for word in paragraph.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                    if ink.width(word) > width {
                        if !line.isEmpty {
                            out.append(line)
                            line = ""
                        }
                        var chunks: [String] = []
                        var chunk = ""
                        for character in word {
                            let probe = chunk + String(character)
                            if !chunk.isEmpty, ink.width(probe) > width {
                                chunks.append(chunk)
                                chunk = String(character)
                            } else {
                                chunk = probe
                            }
                        }
                        if !chunk.isEmpty { chunks.append(chunk) }
                        out.append(contentsOf: chunks.dropLast())
                        line = chunks.last ?? ""
                        continue
                    }
                    let probe = line.isEmpty ? word : "\(line) \(word)"
                    if ink.width(probe) <= width {
                        line = probe
                    } else {
                        if !line.isEmpty { out.append(line) }
                        line = word
                    }
                }
                out.append(line)
            }
            return out
        }
    }

}
