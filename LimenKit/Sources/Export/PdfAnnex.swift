import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// The photo annex, organised the way a handover is walked: a contents list, then one section per
/// room, each opening on a new page under the room's name, then the supplied objects, the meters
/// and anything left. Every photograph sits in a panel with its legend, which repeats the room,
/// so a page met on its own still says where it belongs and what it shows: the finding's number
/// and words as the body prints them, the surface, who is held to it, and when the photograph
/// was taken. No hash: it tells the people at a handover nothing.
///
/// The photographs are large, up to the full width or 1100 units high, 17 cm wide or 19 cm high,
/// at 200 dpi as JPEG. Each is written once as a JPEG into the spool, which the PDF carries as
/// that very stream and the HTML copy embeds as it is, so a record of any size exports.
///
/// The counting pass decodes nothing, but it reads every photograph's size from its header and
/// lays out every legend, so both passes break the pages in the same places.
extension PdfExport.Sheet {
    private static let legendGap: CGFloat = 30
    private static let legendMin: CGFloat = 300
    private static let cardGap: CGFloat = 40
    private static let badge: CGFloat = PdfTokens.badgeHeight
    private static let inner = PdfTokens.width - 2 * PdfTokens.margin - 2 * PdfTokens.framePad

    func annex(_ p: HandoverProtocol, _ photoDir: URL, measuring: Bool) {
        let plates = Report.plates(p)
        if plates.isEmpty { return }
        let sections = AnnexContent.sections(p, s)
        newPage()
        heading(s.pdfDefectAnnex, pill: PdfExport.Pill("\(s.photos): \(plates.count)", .dim))
        if sections.count > 1 {
            // The contents: each section with its photographs and, once counted, its first page.
            // The section marks follow at once, so the anchors are the next marks' in order.
            let next = marks.count
            let entries = sections.enumerated().map { i, section in
                PdfExport.Contents.Entry(title: section.title, level: 0, detail: "\(s.photos): \(section.cards.count)", anchor: anchor(next + i))
            }
            block(PdfExport.Contents(entries, pages: sections.map { annexPages[$0.key] }))
            gap(16)
        }
        for (i, section) in sections.enumerated() {
            if sections.count > 1 || i > 0 { newPage() }
            heading(section.title, level: 1, pill: PdfExport.Pill("\(s.photos): \(section.cards.count)", .dim), key: section.key)
            let layouts = section.cards.compactMap { layout($0, photoDir) }
            if layouts.count != section.cards.count { renderingFailed = true }
            compose(layouts, photoDir, measuring: measuring)
        }
    }

    /// Sets a section's cards on its pages: as many as fit on each, the first under the section's
    /// title, and a page that continues the section with its cards centred on it, so that a
    /// single photograph does not hang from the top of an empty page.
    private func compose(_ cards: [CardLayout], _ photoDir: URL, measuring: Bool) {
        var i = 0
        var underTitle = true
        while i < cards.count {
            // A card that fits a page but not the room under the section's title runs on there too,
            // since a page of its own would leave the title alone above an empty one.
            if !cards[i].fits || (underTitle && y + cards[i].height > PdfTokens.bottom) {
                // The page opened after the last batch is still empty and takes the card as it is.
                if !underTitle, y > PdfTokens.headerBottom { newPage() }
                drawRunOn(cards[i], photoDir, measuring: measuring)
                underTitle = false
                i += 1
                continue
            }
            var used: CGFloat = 0
            var j = i
            while j < cards.count, cards[j].fits, y + used + cards[j].height <= PdfTokens.bottom {
                used += cards[j].height + Self.cardGap
                j += 1
            }
            if j == i {
                newPage()
                underTitle = false
                continue
            }
            if !underTitle { y += (PdfTokens.bottom - y - (used - Self.cardGap)) / 2 }
            for k in i..<j {
                drawCard(cards[k], top: y, photoDir, measuring: measuring)
                y += cards[k].height + Self.cardGap
            }
            i = j
            underTitle = false
            if i < cards.count { newPage() }
        }
    }

    /// A legend line: its text, face, offset from the legend's left edge, and baseline from its top.
    private struct LegendLine {
        let text: String
        let face: PdfExport.Face
        let x: CGFloat
        let baseline: CGFloat
    }

    /// A card's legend laid out at a width: its lines, the finding's badge if any beside line `titleTop`, and its height.
    private struct Legend {
        let lines: [LegendLine]
        let badge: CGRect?
        let number: String?
        let titleTop: Int
        let height: CGFloat
    }

    /// The legend. Wide, under a photograph, it has two columns: where and what on the left,
    /// which photograph and when on the right, set flush right against the frame and as wide as
    /// its longest line, so a file name is never cut. Narrow, beside a tall photograph, the two
    /// stack.
    private func legend(_ card: AnnexContent.Card, width: CGFloat) -> Legend {
        let split = width >= 800
        let metaWidth = split ? min(width * 0.45, (card.meta.map { paints.small.width($0) }.max() ?? 0) + 2) : width
        let mainWidth = split ? width - metaWidth - 40 : width
        var lines: [LegendLine] = []
        var y: CGFloat = 0
        func add(_ text: String, _ face: PdfExport.Face, x: CGFloat, lineWidth: CGFloat, flushRight: Bool = false) {
            for line in PdfExport.TextMeasure.wrapLines(text, face, lineWidth) {
                y += face.size
                lines.append(LegendLine(text: line, face: face, x: flushRight ? width - face.width(line) : x, baseline: y))
                y += 8
            }
        }
        add(card.where.uppercased(), paints.labelSmall, x: 0, lineWidth: mainWidth)
        y += 10
        // The finding's number in a navy badge, its words beside it in bold: the way it reads in the body.
        let number = card.number.map { String($0) }
        let badgeWidth = number.map { paints.badge.width($0) + 24 } ?? 0
        let indent: CGFloat = number != nil ? badgeWidth + 14 : 0
        let titleTop = lines.count
        add(card.title, paints.strong, x: indent, lineWidth: mainWidth - indent)
        let badge: CGRect? = number.map { _ in
            let baseline = lines[titleTop].baseline
            return CGRect(x: 0, y: baseline - paints.strong.size - 2, width: badgeWidth, height: Self.badge)
        }
        if !card.context.isEmpty { y += 4 }
        for line in card.context { add(line, paints.body, x: 0, lineWidth: mainWidth) }
        let main = y
        y = split ? 0 : y + 10
        for line in card.meta { add(line, paints.small, x: 0, lineWidth: metaWidth, flushRight: split) }
        return Legend(lines: lines, badge: badge, number: number, titleTop: titleTop, height: max(main, y) - 8)
    }

    /// Draws `legend`'s badge, if it has one, as if the legend had its top left corner at `left`, `top`.
    private func drawBadge(_ legend: Legend, left: CGFloat, top: CGFloat) {
        guard let badge = legend.badge else { return }
        let box = badge.offsetBy(dx: left, dy: top)
        fillRound(box, radius: PdfTokens.badgeRadius, paints.navyFill)
        let number = legend.number ?? ""
        text(number, box.midX - paints.badge.width(number) / 2, box.minY + paints.badge.baseline(Self.badge), paints.badge)
    }

    /// Draws `legend` with its top left corner at `left`, `top`.
    private func drawLegend(_ legend: Legend, left: CGFloat, top: CGFloat) {
        drawBadge(legend, left: left, top: top)
        for line in legend.lines { text(line.text, left + line.x, top + line.baseline, line.face) }
    }

    /// A card measured before anything is drawn, so a section's pages can be composed first.
    private struct CardLayout {
        let card: AnnexContent.Card
        let fit: AnnexPlate.Fit
        let legend: Legend
        let beside: Bool
        let height: CGFloat
        let fits: Bool
    }

    /// The photograph centred with its legend below, or beside it when a tall photograph leaves
    /// at least `legendMin` there. Read from the file's header, never decoded, so the counting
    /// pass measures what the drawing pass draws.
    private func layout(_ card: AnnexContent.Card, _ photoDir: URL) -> CardLayout? {
        guard let size = PhotoDecode.uprightSize(photoDir.appendingPathComponent(card.file)) else { return nil }
        let fit = AnnexPlate.fit(size.width, size.height)
        let besideWidth = Self.inner - fit.boxWidth - Self.legendGap
        var beside = besideWidth >= Self.legendMin
        var legend = legend(card, width: beside ? besideWidth : Self.inner)
        if beside, legend.height > fit.boxHeight + 200 {
            beside = false
            legend = self.legend(card, width: Self.inner)
        }
        let body = beside ? max(fit.boxHeight, legend.height) : fit.boxHeight + 28 + legend.height
        let height = 2 * PdfTokens.framePad + body
        return CardLayout(card: card, fit: fit, legend: legend, beside: beside, height: height, fits: height <= PdfTokens.bottom - PdfTokens.headerBottom)
    }

    /// One card, its top at `top`: the panel, the photograph in rounded corners under a navy border, the legend.
    private func drawCard(_ layout: CardLayout, top: CGFloat, _ photoDir: URL, measuring: Bool) {
        let fit = layout.fit
        let left = layout.beside ? PdfTokens.margin + PdfTokens.framePad : PdfTokens.margin + PdfTokens.framePad + (Self.inner - fit.boxWidth) / 2
        let photo = CGRect(x: left, y: top + PdfTokens.framePad, width: fit.boxWidth, height: fit.boxHeight)
        frame(top: top, height: layout.height, tone: .raised, radius: PdfTokens.panelRadius)
        plate(layout.card, photoDir.appendingPathComponent(layout.card.file), fit, photo, measuring: measuring)
        if layout.beside {
            drawLegend(layout.legend, left: photo.maxX + Self.legendGap, top: photo.minY)
        } else {
            line(PdfTokens.margin + PdfTokens.framePad, photo.maxY + 14, PdfTokens.width - PdfTokens.margin - PdfTokens.framePad, photo.maxY + 14, paints.edge, 1.5)
            drawLegend(layout.legend, left: PdfTokens.margin + PdfTokens.framePad, top: photo.maxY + 28)
        }
    }

    /// A card laid out as the photograph framed, then the legend running on: for a legend longer
    /// than a page, and for a card that fits a page but not the room under its section title.
    private func drawRunOn(_ layout: CardLayout, _ photoDir: URL, measuring: Bool) {
        let fit = layout.fit
        ensure(2 * PdfTokens.framePad + fit.boxHeight)
        let top = y
        let left = PdfTokens.margin + PdfTokens.framePad + (Self.inner - fit.boxWidth) / 2
        let photo = CGRect(x: left, y: top + PdfTokens.framePad, width: fit.boxWidth, height: fit.boxHeight)
        frame(top: top, height: 2 * PdfTokens.framePad + fit.boxHeight, tone: .raised, radius: PdfTokens.panelRadius)
        plate(layout.card, photoDir.appendingPathComponent(layout.card.file), fit, photo, measuring: measuring)
        y = photo.maxY + PdfTokens.framePad + 16
        let flowing = legend(layout.card, width: 600)
        for (n, line) in flowing.lines.enumerated() {
            ensure(line.face.size + 10)
            // The badge stands by the title's first line, on whichever page the flow has reached.
            if n == flowing.titleTop { drawBadge(flowing, left: PdfTokens.margin + PdfTokens.framePad, top: y + line.face.size - line.baseline) }
            text(line.text, PdfTokens.margin + PdfTokens.framePad + line.x, y + line.face.size, line.face)
            y += line.face.size + 8
        }
        y += Self.cardGap
    }

    /// The photograph in its box, clipped to the app's thumbnail corners under a navy border. The
    /// clip is a path in the page's content stream; the image underneath stays the plain DCT
    /// stream the 1.2.5 pass verified.
    private func plate(_ card: AnnexContent.Card, _ file: URL, _ fit: AnnexPlate.Fit, _ box: CGRect, measuring: Bool) {
        if !measuring { photo(card, file, fit, box) }
        strokeRound(box.insetBy(dx: PdfTokens.border / 2, dy: PdfTokens.border / 2), radius: PdfTokens.thumbRadius, paints.navy, PdfTokens.border)
    }

    /// The photograph itself: decoded upright at its plate size, laid on white when it carries
    /// alpha, written once as a JPEG into the spool, and drawn from that file so the PDF holds the
    /// same bytes the HTML copy embeds.
    private func photo(_ card: AnnexContent.Card, _ file: URL, _ fit: AnnexPlate.Fit, _ box: CGRect) {
        guard let spool else { renderingFailed = true; return }
        let jpeg = spool.appendingPathComponent("plate-\(plateCount).jpg")
        plateCount += 1
        // One pool per plate: ImageIO hands back autoreleased buffers the size of the whole
        // photograph, and the export runs on the main actor, whose pool drains only when the
        // export returns. Without this, thirty 12-megapixel photographs held 1.2 GB at the peak.
        let written = autoreleasepool { () -> Bool in
            guard let decoded = PhotoDecode.uprightAtSize(file, width: fit.pixelWidth, height: fit.pixelHeight),
                  let picture = Self.onPaper(decoded) else { return false }
            // No metadata and no orientation tag: the pixels are already upright, and a plate
            // carries nothing but the picture.
            guard let destination = CGImageDestinationCreateWithURL(jpeg as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
            CGImageDestinationAddImage(destination, picture, [kCGImageDestinationLossyCompressionQuality: AnnexPlate.jpegQuality] as CFDictionary)
            return CGImageDestinationFinalize(destination)
        }
        guard written, plate(jpeg, in: box, radius: PdfTokens.thumbRadius) else { renderingFailed = true; return }
        do { try html?.plate(jpeg, card) } catch { renderingFailed = true }
    }

    /// The plate as paper shows it: a picture with transparency, a screenshot picked from the
    /// gallery, is laid on white. A JPEG carries three colour channels and no alpha, and a
    /// transparent pixel would otherwise encode as black.
    private static func onPaper(_ image: CGImage) -> CGImage? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
