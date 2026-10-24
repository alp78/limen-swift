import CoreGraphics
import Foundation
import UIKit

extension PdfExport {
    /// A panel's look: the app's raised panel, or its amber warning panel.
    enum Tone: String {
        case raised, warning
    }

    /// Seal: navy, white lettering. Warning: amber. Dim: the input grey. Paper: white on the navy banner.
    enum PillTone: String {
        case seal, warning, dim, paper
    }

    struct Pill {
        let text: String
        let tone: PillTone

        init(_ text: String, _ tone: PillTone) {
            self.text = text
            self.tone = tone
        }
    }

    /// The app's panel on paper: a title in small capitals, a pill at the right, blocks under
    /// them. `inContents` lists it on the cover at `level`; `key` names it to the annex.
    struct Panel {
        let title: String
        let blocks: [any Block]
        let pill: Pill?
        let tone: Tone
        let inContents: Bool
        let level: Int
        let key: String?

        init(_ title: String, _ blocks: [any Block], pill: Pill? = nil, tone: Tone = .raised, inContents: Bool = true, level: Int = 0, key: String? = nil) {
            self.title = title
            self.blocks = blocks
            self.pill = pill
            self.tone = tone
            self.inContents = inContents
            self.level = level
            self.key = key
        }
    }

    /// Where a section opened: its title, its page, its depth in the contents, and the key the annex knows it by.
    struct Mark: Equatable {
        let title: String
        let page: Int
        let level: Int
        let key: String?
    }

    struct RenderPass {
        /// The PDF's bytes when the sheet drew into memory, which only the counting pass and the
        /// glyph test do; a sheet drawing into a file leaves this nil.
        let data: Data?
        let pages: Int
        /// Every section as it opened, in order: the contents and the check between the passes.
        let marks: [Mark]
    }

    /// Where a sheet's pages go: into a file beside its HTML and the spool of plate JPEGs, or into
    /// memory for the counting pass, which draws no photograph and writes no HTML.
    enum Output {
        case files(pdf: URL, html: URL, spool: URL)
        case memory
    }

    /// The pages: cursor, running header, footer, and the one way a section draws anything, which
    /// is a `panel` or a `heading`. Every page after the cover carries the record's kind, its
    /// address and its reference, so a sheet separated from the rest still says what it belongs
    /// to; the footer's "n / N" is the tamper evidence paper has always used.
    final class Sheet {
        static let pillPad: CGFloat = 16

        let s: Str
        let reference: String
        private let kindLine: String
        private let addressLine: String
        let total: Int
        let paints = Paints()
        let html: HtmlSink?
        let spool: URL?
        /// The seal, decoded once per pass and drawn on every page from the same image, which the
        /// PDF context then embeds once.
        let logo: CGImage?
        /// The page each annex section opened on in the counting pass, by section key; empty while counting.
        let annexPages: [String: Int]
        private(set) var marks: [Mark] = []
        private(set) var pageNo = 0
        private var pageOpen = false
        var onPage: Bool { pageOpen }
        var y: CGFloat = 0
        var plateCount = 0
        var renderingFailed = false
        /// The width inside a panel.
        let inner = PdfTokens.width - 2 * PdfTokens.margin - 2 * PdfTokens.panelPad
        private let data = NSMutableData()
        private var consumer: CGDataConsumer?
        private var pdf: CGContext?

        init(s: Str, reference: String, kindLine: String = "", addressLine: String = "", total: Int,
             output: Output = .memory, logo: CGImage? = nil, annexPages: [String: Int] = [:]) throws {
            self.s = s
            self.reference = reference
            self.kindLine = kindLine
            self.addressLine = addressLine
            self.total = total
            self.logo = logo
            self.annexPages = annexPages
            switch output {
            case .files(let pdfURL, let htmlURL, let spoolURL):
                try FileManager.default.createDirectory(at: spoolURL, withIntermediateDirectories: true)
                guard let consumer = CGDataConsumer(url: pdfURL as CFURL) else { throw ExportError.rendering }
                self.consumer = consumer
                html = try HtmlSink(url: htmlURL, language: s.lang, title: "Limen \(reference)")
                spool = spoolURL
            case .memory:
                guard let consumer = CGDataConsumer(data: data) else { throw ExportError.rendering }
                self.consumer = consumer
                html = nil
                spool = nil
            }
            guard let consumer, let pdf = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw ExportError.rendering }
            self.pdf = pdf
        }

        func newPage(cover: Bool = false) {
            finish()
            pageNo += 1
            guard let pdf else { return }
            var box = CGRect(origin: .zero, size: a4)
            pdf.beginPage(mediaBox: &box)
            // PDF space runs upward from the bottom left; the sheet is drawn top down in its own
            // units, so the page is flipped and scaled once here and every drawing call below
            // reads exactly like the Android one.
            pdf.translateBy(x: 0, y: a4.height)
            pdf.scaleBy(x: a4.width / PdfTokens.width, y: -a4.height / PdfTokens.height)
            pdf.setFillColor(paints.paperFill.cgColor)
            pdf.fill(CGRect(x: 0, y: 0, width: PdfTokens.width, height: PdfTokens.height))
            pageOpen = true
            if cover {
                y = PdfTokens.margin
            } else {
                runningHeader()
                y = PdfTokens.headerBottom
            }
        }

        private func runningHeader() {
            if let logo { image(logo, in: CGRect(x: PdfTokens.margin, y: 48, width: 36, height: 36)) }
            text(kindLine.uppercased(), PdfTokens.margin + 50, 76, paints.labelSmall)
            let address = TextMeasure.ellipsize(addressLine, paints.small, 700)
            text(address, PdfTokens.width - PdfTokens.margin - paints.small.width(address), 62, paints.small)
            text(reference, PdfTokens.width - PdfTokens.margin - paints.small.width(reference), 88, paints.small)
            line(PdfTokens.margin, 102, PdfTokens.width - PdfTokens.margin, 102, paints.edge, 1.5)
        }

        func finish() {
            guard pageOpen, let pdf else { return }
            let rule = PdfTokens.height - PdfTokens.foot - 14
            line(PdfTokens.margin, rule, PdfTokens.width - PdfTokens.margin, rule, paints.edge, 1.5)
            let baseline = PdfTokens.height - PdfTokens.foot + 8
            text(reference, PdfTokens.margin, baseline, paints.small)
            let pageText = total > 0 ? "\(s.pdfPage) \(pageNo) / \(total)" : "\(s.pdfPage) \(pageNo)"
            text(pageText, PdfTokens.width - PdfTokens.margin - paints.small.width(pageText), baseline, paints.small)
            pdf.endPage()
            pageOpen = false
        }

        func close() throws -> RenderPass {
            finish()
            pdf?.closePDF()
            try html?.finish()
            guard !renderingFailed, pdf != nil else { throw ExportError.rendering }
            return RenderPass(data: html == nil ? data as Data : nil, pages: pageNo, marks: marks)
        }

        /// Guarantees `need` vertical units, breaking the page when they are not there.
        func ensure(_ need: CGFloat) {
            if !pageOpen || y + need > PdfTokens.bottom { newPage() }
        }

        func gap(_ v: CGFloat) { y += v }

        /// Records where a section opened and returns the anchor its HTML carries.
        @discardableResult
        func mark(_ title: String, level: Int, key: String? = nil) -> String {
            marks.append(Mark(title: title, page: pageNo, level: level, key: key))
            return anchor(marks.count - 1)
        }

        func anchor(_ index: Int) -> String { "c\(index)" }

        /// Draws `pill` with its right edge at `right`, and returns its width.
        @discardableResult
        func pill(_ pill: Pill, right: CGFloat, top: CGFloat) -> CGFloat {
            let text = pill.text.uppercased()
            let face: Face
            switch pill.tone {
            case .seal: face = paints.pillSeal
            case .warning: face = paints.pillWarning
            case .dim: face = paints.pillDim
            case .paper: face = paints.pillPaper
            }
            let width = face.width(text) + 2 * Sheet.pillPad
            let box = CGRect(x: right - width, y: top, width: width, height: PdfTokens.pillHeight)
            switch pill.tone {
            case .seal:
                fillRound(box, radius: PdfTokens.pillRadius, paints.navyFill)
            case .warning:
                fillRound(box, radius: PdfTokens.pillRadius, paints.warningFill)
                strokeRound(box.insetBy(dx: PdfTokens.border / 2, dy: PdfTokens.border / 2), radius: PdfTokens.pillRadius, paints.warningOutline, PdfTokens.border)
            case .dim:
                fillRound(box, radius: PdfTokens.pillRadius, paints.inputFill)
            case .paper:
                fillRound(box, radius: PdfTokens.pillRadius, paints.paperFill)
            }
            self.text(text, right - width + Sheet.pillPad, top + face.baseline(PdfTokens.pillHeight), face)
            return width
        }

        /// What a panel's frame, title and pill take of a page before any row does.
        private let chrome = 2 * PdfTokens.panelPad + PdfTokens.pillHeight + PdfTokens.labelGap

        /// A section heading over a navy rule, the hub door's title: for a group of panels.
        /// `first` is the panel that follows, so the heading moves to a fresh page when that panel
        /// would not open under it and the heading would stay behind alone.
        func heading(_ title: String, level: Int = 0, pill: Pill? = nil, key: String? = nil, first: Panel? = nil) {
            let line = paints.line(of: .title)
            ensure(headingNeed(line, first))
            let anchor = mark(title, level: level, key: key)
            html?.heading(title, anchor: anchor)
            var max = PdfTokens.width - 2 * PdfTokens.margin
            if let pill { max -= self.pill(pill, right: PdfTokens.width - PdfTokens.margin, top: y + (line - PdfTokens.pillHeight) / 2) + 20 }
            text(TextMeasure.ellipsize(title, paints.title, max), PdfTokens.margin, y + paints.title.baseline(line), paints.title)
            y += line + 10
            self.line(PdfTokens.margin, y, PdfTokens.width - PdfTokens.margin, y, paints.navy, PdfTokens.border)
            y += 24
        }

        /// What a heading reserves: room for `first` to open under it, which is the heading, the
        /// panel's chrome and the rows it cannot open without. `headingNeed` when there is no
        /// panel to ask, and when the panel could not open under a heading even on a fresh page,
        /// since moving the heading would then strand it at the top of that page instead.
        private func headingNeed(_ line: CGFloat, _ first: Panel?) -> CGFloat {
            guard let first else { return PdfTokens.headingNeed }
            let rows = first.blocks.flatMap { $0.rows(paints, width: inner) }
            let need = line + 10 + 24 + chrome + Paginator.opening(rows.map { Paginator.Slot($0.height, keepWithNext: $0.keepWithNext) }, full: PdfTokens.bottom - PdfTokens.headerBottom - chrome)
            return need > PdfTokens.bottom - PdfTokens.headerBottom ? PdfTokens.headingNeed : Swift.max(need, PdfTokens.headingNeed)
        }

        /// Draws `panel`, whole when it fits the space left, otherwise in closed segments, each a
        /// complete panel with the title repeated and a "continued" pill, so no page ends on an
        /// open shape. The HTML is written once, before the first segment.
        func panel(_ panel: Panel) {
            let rows = panel.blocks.flatMap { $0.rows(paints, width: inner) }
            let available = pageOpen ? PdfTokens.bottom - y - chrome : -1
            let full = PdfTokens.bottom - PdfTokens.headerBottom - chrome
            let segments = Paginator.segments(rows.map { Paginator.Slot($0.height, keepWithNext: $0.keepWithNext) }, available: available, full: full)
            if let html {
                let anchor = panel.inContents ? anchor(marks.count) : nil
                html.panel(panel.title, tone: panel.tone.rawValue, pill: panel.pill?.text, pillTone: panel.pill?.tone.rawValue, anchor: anchor) {
                    for block in panel.blocks { block.html(html) }
                }
            }
            for segment in segments {
                if segment.newPageBefore || !pageOpen { newPage() }
                let height = chrome + rows[segment.from..<segment.to].reduce(0) { $0 + $1.height }
                frame(top: y, height: height, tone: panel.tone, radius: PdfTokens.panelRadius)
                if !segment.continued, panel.inContents { mark(panel.title, level: panel.level, key: panel.key) }
                let left = PdfTokens.margin + PdfTokens.panelPad
                let top = y + PdfTokens.panelPad
                let pill = segment.continued ? Pill(s.continued, .dim) : panel.pill
                var titleMax = inner
                if let pill { titleMax -= self.pill(pill, right: PdfTokens.width - PdfTokens.margin - PdfTokens.panelPad, top: top) + 20 }
                // A room's panel is titled like a hub door, in the bold label; a component's like a panel.
                let titleFace = panel.level > 0 ? paints.labelLarge : paints.labelSmall
                text(TextMeasure.ellipsize(panel.title.uppercased(), titleFace, titleMax), left, top + titleFace.baseline(PdfTokens.pillHeight), titleFace)
                var rowTop = top + PdfTokens.pillHeight + PdfTokens.labelGap
                for i in segment.from..<segment.to {
                    rows[i].draw(self, left, rowTop)
                    rowTop += rows[i].height
                }
                y += height + PdfTokens.panelGap
            }
        }

        /// The panel's shape: the fill, then the border inset by half its width so it stays inside the margin.
        func frame(top: CGFloat, height: CGFloat, tone: Tone, radius: CGFloat, left: CGFloat = PdfTokens.margin, right: CGFloat = PdfTokens.width - PdfTokens.margin) {
            let box = CGRect(x: left, y: top, width: right - left, height: height)
            fillRound(box, radius: radius, tone == .warning ? paints.warningFill : paints.panelFill)
            strokeRound(box.insetBy(dx: PdfTokens.border / 2, dy: PdfTokens.border / 2), radius: radius, tone == .warning ? paints.warningOutline : paints.navy, PdfTokens.border)
        }

        /// A block outside any panel, split row by row across pages.
        func block(_ block: any Block) {
            if let html { block.html(html) }
            for row in block.rows(paints, width: PdfTokens.width - 2 * PdfTokens.margin) {
                ensure(row.height)
                row.draw(self, PdfTokens.margin, y)
                y += row.height
            }
        }

        // MARK: Drawing primitives, and nothing else: flat fills and strokes, lines, text, a bitmap

        /// Draws with the baseline at `baseline`, the way Canvas.drawText places its text.
        func text(_ string: String, _ x: CGFloat, _ baseline: CGFloat, _ face: Face) {
            guard let pdf else { renderingFailed = true; return }
            UIGraphicsPushContext(pdf)
            // NSString's UIKit drawing expects the top-down context established by newPage. A
            // second local flip makes every glyph upside down while text extraction still passes.
            (string as NSString).draw(at: CGPoint(x: x, y: baseline - face.font.ascender), withAttributes: face.attributes)
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

        private func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
            let r = min(radius, rect.width / 2, rect.height / 2)
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        }

        func fillRound(_ rect: CGRect, radius: CGFloat, _ colour: UIColor) {
            guard let pdf else { return }
            pdf.setFillColor(colour.cgColor)
            pdf.addPath(rounded(rect, radius))
            pdf.fillPath()
        }

        func strokeRound(_ rect: CGRect, radius: CGFloat, _ colour: UIColor, _ width: CGFloat) {
            guard let pdf else { return }
            pdf.setStrokeColor(colour.cgColor)
            pdf.setLineWidth(width)
            pdf.addPath(rounded(rect, radius))
            pdf.strokePath()
        }

        /// A signature or the seal, drawn from its bitmap.
        func image(_ image: CGImage, in rect: CGRect) {
            guard let pdf else { return }
            pdf.saveGState()
            draw(image, in: rect, pdf)
            pdf.restoreGState()
        }

        /// An annex plate: the JPEG file itself under a rounded clip. A `CGImage` made from a
        /// JPEG data provider goes into the PDF as its original DCT stream, so the page carries
        /// the very bytes the HTML copy embeds and nothing is re-encoded; the clip is a path in
        /// the content stream and leaves the image object as it is.
        func plate(_ jpeg: URL, in rect: CGRect, radius: CGFloat) -> Bool {
            guard let pdf, let provider = CGDataProvider(url: jpeg as CFURL),
                  let image = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return false }
            pdf.saveGState()
            pdf.addPath(rounded(rect, radius))
            pdf.clip()
            draw(image, in: rect, pdf)
            pdf.restoreGState()
            return true
        }

        private func draw(_ image: CGImage, in rect: CGRect, _ pdf: CGContext) {
            pdf.translateBy(x: rect.minX, y: rect.maxY)
            pdf.scaleBy(x: 1, y: -1)
            pdf.interpolationQuality = .high
            pdf.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        }
    }
}
