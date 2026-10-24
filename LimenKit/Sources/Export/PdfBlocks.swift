import CoreGraphics
import Foundation
import UIKit

extension PdfExport {
    /// One atomic row of a panel, `height` tall, drawn with its top left corner at (left, top).
    struct Row {
        let height: CGFloat
        let keepWithNext: Bool
        let draw: (Sheet, CGFloat, CGFloat) -> Void

        init(_ height: CGFloat, keepWithNext: Bool = false, draw: @escaping (Sheet, CGFloat, CGFloat) -> Void) {
            self.height = height
            self.keepWithNext = keepWithNext
            self.draw = draw
        }

        /// The same row, holding on to its successor.
        func kept() -> Row { Row(height, keepWithNext: true, draw: draw) }
    }

    /// A unit of content that lays itself out as rows at a given width and writes itself to the
    /// HTML copy once. The content is built once and both outputs read it, so the preview on the
    /// screen and the paper cannot say different things.
    protocol Block {
        func rows(_ p: Paints, width: CGFloat) -> [Row]
        func html(_ h: HtmlSink)
    }

    enum TextMeasure {
        static func wrapLines(_ text: String, _ face: Face, _ width: CGFloat) -> [String] {
            var out: [String] = []
            for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
                var line = ""
                for word in paragraph.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                    if face.width(word) > width {
                        if !line.isEmpty {
                            out.append(line)
                            line = ""
                        }
                        var chunks: [String] = []
                        var chunk = ""
                        for character in word {
                            let probe = chunk + String(character)
                            if !chunk.isEmpty, face.width(probe) > width {
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
                    if face.width(probe) <= width {
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

        static func ellipsize(_ text: String, _ face: Face, _ width: CGFloat) -> String {
            if face.width(text) <= width { return text }
            var t = text
            while !t.isEmpty, face.width("\(t)…") > width { t.removeLast() }
            return "\(t)…"
        }
    }

    /// Wrapped text, one row per line.
    struct Text: Block {
        let text: String
        let style: Style
        let indent: CGFloat
        let keepWithNext: Bool

        init(_ text: String, _ style: Style = .body, indent: CGFloat = 0, keepWithNext: Bool = false) {
            self.text = text
            self.style = style
            self.indent = indent
            self.keepWithNext = keepWithNext
        }

        func rows(_ p: Paints, width: CGFloat) -> [Row] {
            let face = p.of(style)
            let line = p.line(of: style)
            return TextMeasure.wrapLines(text, face, width - indent).map { words in
                Row(line, keepWithNext: keepWithNext) { sheet, l, t in sheet.text(words, l + indent, t + face.baseline(line), face) }
            }
        }

        func html(_ h: HtmlSink) { h.text(text) }
    }

    /// One line that never wraps, cut with an ellipsis: one row high whatever its words, in both passes.
    struct Line: Block {
        let text: String
        let style: Style
        let indent: CGFloat

        init(_ text: String, _ style: Style = .small, indent: CGFloat = 0) {
            self.text = text
            self.style = style
            self.indent = indent
        }

        func rows(_ p: Paints, width: CGFloat) -> [Row] {
            let face = p.of(style)
            let line = p.line(of: style)
            let words = TextMeasure.ellipsize(text, face, width - indent)
            return [Row(line) { sheet, l, t in sheet.text(words, l + indent, t + face.baseline(line), face) }]
        }

        func html(_ h: HtmlSink) { h.text(text) }
    }

    struct Gap: Block {
        let height: CGFloat

        init(_ height: CGFloat) { self.height = height }

        func rows(_ p: Paints, width: CGFloat) -> [Row] { [Row(height) { _, _, _ in }] }
        func html(_ h: HtmlSink) {}
    }

    /// Labels over values in `columns` equal columns, the way the app's fields sit on a panel.
    /// Each grid row is one atomic row; a value too long for a page paginates as plain rows.
    struct Fields: Block {
        let pairs: [(String, String)]
        let columns: Int

        init(_ pairs: [(String, String)], columns: Int? = nil) {
            self.pairs = pairs
            self.columns = max(1, columns ?? pairs.count)
        }

        func rows(_ p: Paints, width: CGFloat) -> [Row] {
            let label = p.labelSmall
            let value = p.bodyLarge
            let labelLine = p.line(of: .labelSmall)
            let valueLine = p.line(of: .bodyLarge)
            let colWidth = width / CGFloat(columns)
            var out: [Row] = []
            for start in stride(from: 0, to: pairs.count, by: columns) {
                let chunk = Array(pairs[start..<min(start + columns, pairs.count)])
                let cols = chunk.map { heading, entry in
                    (TextMeasure.wrapLines(heading, label, colWidth - 18), TextMeasure.wrapLines(entry.ifBlank("–"), value, colWidth - 18))
                }
                let labelLines = cols.map { $0.0.count }.max() ?? 0
                let valueLines = cols.map { $0.1.count }.max() ?? 0
                let height = CGFloat(labelLines) * labelLine + CGFloat(valueLines) * valueLine + PdfTokens.labelGap
                if height > PdfTokens.bottom - PdfTokens.headerBottom - 200 {
                    // An unusually long legal name or address paginates rather than running off the paper.
                    for (heading, entry) in chunk {
                        out += Text(heading, .labelSmall, keepWithNext: true).rows(p, width: width)
                        out += Text(entry.ifBlank("–"), .bodyLarge).rows(p, width: width)
                    }
                    continue
                }
                out.append(Row(height) { sheet, l, t in
                    for (i, column) in cols.enumerated() {
                        let x = l + CGFloat(i) * colWidth
                        for (n, words) in column.0.enumerated() {
                            sheet.text(words, x, t + CGFloat(n) * labelLine + label.baseline(labelLine), label)
                        }
                        let valueTop = t + CGFloat(labelLines) * labelLine
                        for (n, words) in column.1.enumerated() {
                            sheet.text(words, x, valueTop + CGFloat(n) * valueLine + value.baseline(valueLine), value)
                        }
                    }
                })
            }
            return out
        }

        func html(_ h: HtmlSink) { h.fields(pairs) }
    }

    /// `html` is what the accessible copy says when the page's wording means nothing there, such as a page number.
    struct Chip {
        let text: String
        let active: Bool
        let html: String

        init(_ text: String, active: Bool = false, html: String? = nil) {
            self.text = text
            self.active = active
            self.html = html ?? text
        }
    }

    /// A wrapping row of chips, the app's pill row: one row per wrapped line.
    struct Chips: Block {
        static let height: CGFloat = PdfTokens.chipHeight
        static let pad: CGFloat = 14

        let chips: [Chip]
        let indent: CGFloat
        let keepWithNext: Bool

        init(_ chips: [Chip], indent: CGFloat = 0, keepWithNext: Bool = false) {
            self.chips = chips
            self.indent = indent
            self.keepWithNext = keepWithNext
        }

        private struct Placed {
            let chip: Chip
            let x: CGFloat
            let width: CGFloat
        }

        func rows(_ p: Paints, width: CGFloat) -> [Row] {
            if chips.isEmpty { return [] }
            let avail = width - indent
            var lines: [[Placed]] = []
            var x: CGFloat = 0
            for chip in chips {
                let text = TextMeasure.ellipsize(chip.text, p.chip, avail - 2 * Chips.pad)
                let w = p.chip.width(text) + 2 * Chips.pad
                if lines.isEmpty || (x + w > avail && !(lines.last?.isEmpty ?? true)) {
                    lines.append([])
                    x = 0
                }
                lines[lines.count - 1].append(Placed(chip: Chip(text, active: chip.active, html: chip.html), x: x, width: w))
                x += w + PdfTokens.chipGap
            }
            return lines.map { line in
                Row(Chips.height + PdfTokens.chipGap, keepWithNext: keepWithNext) { sheet, l, t in
                    for placed in line { Chips.draw(sheet, p, placed.chip, x: l + indent + placed.x, top: t, width: placed.width) }
                }
            }
        }

        private static func draw(_ sheet: Sheet, _ p: Paints, _ chip: Chip, x: CGFloat, top: CGFloat, width: CGFloat) {
            let box = CGRect(x: x, y: top, width: width, height: height)
            if chip.active {
                sheet.fillRound(box, radius: PdfTokens.chipRadius, p.navyFill)
            } else {
                sheet.fillRound(box, radius: PdfTokens.chipRadius, p.inputFill)
                sheet.strokeRound(box.insetBy(dx: 0.5, dy: 0.5), radius: PdfTokens.chipRadius, p.edge, 1)
            }
            let face = chip.active ? p.chipActive : p.chip
            sheet.text(chip.text, x + pad, top + face.baseline(height), face)
        }

        func html(_ h: HtmlSink) { h.chips(chips.map { ($0.html, $0.active) }) }
    }

    /// One numbered finding: the number in a navy badge beside where it was found, then its
    /// words, its chips, the notes hanging on it and each participant's position.
    struct Finding: Block {
        static let indent: CGFloat = 48
        static let badge: CGFloat = PdfTokens.badgeHeight

        let number: Int
        let `where`: String
        let text: String
        let chips: [Chip]
        let notes: [String]
        let positions: [String]

        func rows(_ p: Paints, width: CGFloat) -> [Row] {
            let numberText = String(number)
            let badgeWidth = p.badge.width(numberText) + 24
            let indent = max(Finding.indent, badgeWidth + 14)
            let whereText = TextMeasure.ellipsize(`where`.uppercased(), p.labelSmall, width - indent)
            var out: [Row] = []
            out.append(Row(Finding.badge + 6, keepWithNext: true) { sheet, l, t in
                sheet.fillRound(CGRect(x: l, y: t, width: badgeWidth, height: Finding.badge), radius: PdfTokens.badgeRadius, p.navyFill)
                sheet.text(numberText, l + (badgeWidth - p.badge.width(numberText)) / 2, t + p.badge.baseline(Finding.badge), p.badge)
                if !whereText.isBlank { sheet.text(whereText, l + indent, t + p.labelSmall.baseline(Finding.badge), p.labelSmall) }
            })
            // Every row holds on to the next, so a finding that fits a page moves to it whole and
            // a cost note never opens a page on its own; only the closing gap lets a page end.
            out += Text(text.ifBlank("–"), .body, indent: indent).rows(p, width: width).map { $0.kept() }
            out += Chips(chips, indent: indent).rows(p, width: width).map { $0.kept() }
            for note in notes { out += Text(note, .small, indent: indent).rows(p, width: width).map { $0.kept() } }
            for position in positions { out += Text(position, .body, indent: indent).rows(p, width: width).map { $0.kept() } }
            out.append(Row(PdfTokens.labelGap) { _, _, _ in })
            return out
        }

        func html(_ h: HtmlSink) {
            h.finding(number, `where`) {
                h.text(text.ifBlank("–"))
                if !chips.isEmpty { h.chips(chips.map { ($0.html, $0.active) }) }
                for note in notes { h.text(note) }
                for position in positions { h.text(position) }
            }
        }
    }

    /// The exhaustive item grid older records were signed with: two columns, the state at the right of each.
    struct ItemGrid: Block {
        let lines: [(String, String)]

        init(_ lines: [(String, String)]) { self.lines = lines }

        func rows(_ p: Paints, width: CGFloat) -> [Row] {
            let colWidth = (width - 40) / 2
            let stateWidth: CGFloat = 140
            let line = p.line(of: .body)
            let rowsPerCol = (lines.count + 1) / 2
            return (0..<rowsPerCol).map { i in
                Row(line) { sheet, l, t in
                    for col in 0..<2 {
                        let index = i + col * rowsPerCol
                        guard index < lines.count else { continue }
                        let (name, state) = lines[index]
                        let x = l + CGFloat(col) * (colWidth + 40)
                        sheet.text(TextMeasure.ellipsize(name, p.body, colWidth - stateWidth - 20), x, t + p.body.baseline(line), p.body)
                        let stateText = TextMeasure.ellipsize(state, p.bodyMedium, stateWidth)
                        sheet.text(stateText, x + colWidth - p.bodyMedium.width(stateText), t + p.bodyMedium.baseline(line), p.bodyMedium)
                    }
                }
            }
        }

        func html(_ h: HtmlSink) { h.fields(lines) }
    }

    /// A signature: the ink over a rule, or the note that stands for it, then its caption rows.
    /// The bitmap is drawn straight onto the page and Core Graphics embeds it itself.
    struct Ink: Block {
        static let maxWidth: CGFloat = 420
        static let maxHeight: CGFloat = 130

        let image: CGImage?
        let alt: String
        let note: String?
        let caption: [any Block]

        func rows(_ p: Paints, width: CGFloat) -> [Row] {
            var out: [Row] = []
            if let note {
                out += Text(note, .body, keepWithNext: true).rows(p, width: width)
            } else if let image {
                let scale = min(Ink.maxWidth / CGFloat(image.width), Ink.maxHeight / CGFloat(image.height), 1)
                let w = CGFloat(image.width) * scale
                let h = CGFloat(image.height) * scale
                out.append(Row(h + 18, keepWithNext: true) { sheet, l, t in
                    sheet.image(image, in: CGRect(x: l, y: t, width: w, height: h))
                    sheet.line(l, t + h + 8, l + Ink.maxWidth, t + h + 8, p.edge, 1.5)
                })
            } else {
                out.append(Row(18, keepWithNext: true) { sheet, l, t in sheet.line(l, t + 8, l + Ink.maxWidth, t + 8, p.edge, 1.5) })
            }
            for block in caption { out += block.rows(p, width: width) }
            out.append(Row(14) { _, _, _ in })
            return out
        }

        func html(_ h: HtmlSink) {
            if let image, note == nil, let png = UIImage(cgImage: image).pngData() { h.image(png: png, alt: alt) }
            if let note { h.text(note) }
            for block in caption { block.html(h) }
        }
    }

    /// A contents list: each entry's title, an optional detail and its page, the page column of
    /// fixed width so the counting pass, which knows no pages yet, lays the rows out as the
    /// drawing pass does.
    struct Contents: Block {
        static let pageColumn: CGFloat = 100

        struct Entry {
            let title: String
            let level: Int
            let detail: String?
            let anchor: String?

            init(title: String, level: Int, detail: String? = nil, anchor: String? = nil) {
                self.title = title
                self.level = level
                self.detail = detail
                self.anchor = anchor
            }
        }

        let entries: [Entry]
        let pages: [Int?]

        init(_ entries: [Entry], pages: [Int?]) {
            self.entries = entries
            self.pages = pages
        }

        func rows(_ p: Paints, width: CGFloat) -> [Row] {
            entries.enumerated().map { i, entry in
                let face = entry.level == 0 ? p.body : p.small
                let line = p.line(of: entry.level == 0 ? .body : .small)
                let indent = CGFloat(entry.level) * 32
                let pageText = i < pages.count ? pages[i].map(String.init) ?? "" : ""
                return Row(line) { sheet, l, t in
                    let base = t + face.baseline(line)
                    let right = l + width
                    sheet.text(pageText, right - face.width(pageText), base, face)
                    var titleMax = width - indent - Contents.pageColumn
                    if let detail = entry.detail {
                        let detailWidth = p.small.width(detail)
                        sheet.text(detail, right - Contents.pageColumn - detailWidth, t + p.small.baseline(line), p.small)
                        titleMax -= detailWidth + 40
                    }
                    sheet.text(TextMeasure.ellipsize(entry.title, face, titleMax), l + indent, base, face)
                }
            }
        }

        func html(_ h: HtmlSink) {
            h.contents(entries.map { HtmlSink.ContentsEntry(title: $0.title, level: $0.level, detail: $0.detail, anchor: $0.anchor) })
        }
    }
}
