import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// The photo annex of the document, in its own file because it is a document of its own: the
/// body cites photographs by number and the annex prints them, and the two meet only in the
/// numbering `Report` fixes.
extension PdfExport {
    // MARK: The photo annex

    /// The photo annex, organised the way a handover is walked: a contents page, then one section
    /// per room, each opening on a new page under the room's title, then the supplied objects,
    /// the meters and anything left. Every photograph sits in a frame with its legend, which
    /// repeats the room, so a page met on its own still says where it belongs and what it shows:
    /// the finding's number and words as the body prints them, the surface, who is held to it,
    /// and when the photograph was taken. No hash: it tells the people at a handover nothing.
    ///
    /// The photographs are large, up to the full width or 1100 units high, 17 cm wide or 19 cm
    /// high, at 200 dpi as JPEG, which keeps thirty of them to a PDF of a few megabytes. Each is
    /// written once as a JPEG into the spool, which the PDF carries as that very stream and the
    /// HTML copy embeds as it is.
    ///
    /// The counting pass decodes nothing, but it reads every photograph's size from its header
    /// and lays out every legend, so both passes break the pages in the same places.
    static func annex(_ sheet: Sheet, _ p: HandoverProtocol, _ s: Str, _ photoDir: URL, measuring: Bool) {
        let plates = Report.plates(p)
        if plates.isEmpty { return }
        let sections = AnnexContent.sections(p, s)
        sheet.newPage()
        sheet.sectionTitle(s.pdfDefectAnnex)
        if sections.count > 1 {
            // The contents: each section with its photographs and, once counted, its first page.
            for (index, section) in sections.enumerated() {
                let count = "\(s.photos): \(section.cards.count)"
                let page = index < sheet.contents.count ? "\(s.pdfPage) \(sheet.contents[index])" : ""
                sheet.html?.text([section.title, count, page].filter { !$0.isBlank }.joined(separator: " · "))
                sheet.ensure(sheet.body.size + 18)
                let baseline = sheet.y + sheet.body.size
                sheet.suppressHTML = true
                sheet.text(sheet.ellipsize(section.title, sheet.body, 640), margin, baseline, sheet.body)
                sheet.text(count, margin + 680, baseline, sheet.small)
                sheet.text(page, pageWidth - margin - sheet.small.width(page), baseline, sheet.small)
                sheet.suppressHTML = false
                sheet.y += sheet.body.size + 10
                sheet.line(margin, sheet.y, pageWidth - margin, sheet.y, sheet.ruleColour, 1.5)
                sheet.y += 8
            }
        }
        for (index, section) in sections.enumerated() {
            if sections.count > 1 || index > 0 { sheet.newPage() }
            sheet.sectionStarts.append(sheet.pageNo)
            sectionHeader(sheet, section, s)
            let layouts = section.cards.compactMap { layout(sheet, $0, photoDir) }
            if layouts.count != section.cards.count { sheet.renderingFailed = true }
            compose(sheet, layouts, photoDir, measuring: measuring)
        }
    }

    /// Sets a section's cards on its pages: as many as fit on each, the first under the section's
    /// title, and a page that continues the section with its cards centred on it, so that a
    /// single photograph does not hang from the top of an empty page.
    private static func compose(_ sheet: Sheet, _ cards: [CardLayout], _ photoDir: URL, measuring: Bool) {
        let bottom = pageHeight - foot - 30
        var i = 0
        var underTitle = true
        while i < cards.count {
            if !cards[i].fits {
                if !underTitle { sheet.newPage() }
                drawRunOn(sheet, cards[i], photoDir, measuring: measuring)
                underTitle = false
                i += 1
                continue
            }
            var used: CGFloat = 0
            var j = i
            while j < cards.count, cards[j].fits, sheet.y + used + cards[j].height <= bottom {
                used += cards[j].height + cardGap
                j += 1
            }
            if j == i {
                sheet.newPage()
                underTitle = false
                continue
            }
            if !underTitle { sheet.y += (bottom - sheet.y - (used - cardGap)) / 2 }
            for k in i..<j {
                drawCard(sheet, cards[k], top: sheet.y, photoDir, measuring: measuring)
                sheet.y += cards[k].height + cardGap
            }
            i = j
            underTitle = false
            if i < cards.count { sheet.newPage() }
        }
    }

    /// A section's title band: the room in capitals over a heavy rule, its photo count at the right.
    private static func sectionHeader(_ sheet: Sheet, _ section: AnnexContent.Section, _ s: Str) {
        sheet.html?.subheading(section.title)
        sheet.suppressHTML = true
        defer { sheet.suppressHTML = false }
        let baseline = sheet.y + sheet.roomTitle.size
        let count = "\(s.photos): \(section.cards.count)"
        let countWidth = sheet.small.width(count)
        sheet.text(sheet.ellipsize(section.title.uppercased(), sheet.roomTitle, pageWidth - 2 * margin - countWidth - 30), margin, baseline, sheet.roomTitle)
        sheet.text(count, pageWidth - margin - countWidth, baseline, sheet.small)
        sheet.y = baseline + 16
        sheet.line(margin, sheet.y, pageWidth - margin, sheet.y, sheet.heavyRuleColour, 4)
        sheet.y += 30
    }

    /// A legend line: its text, ink, offset from the legend's left edge, and baseline from its top.
    private struct LegendLine {
        let text: String
        let ink: Ink
        let x: CGFloat
        let baseline: CGFloat
    }

    /// A card's legend laid out at a width: its lines, the finding's badge if any, and its height.
    private struct Legend {
        let lines: [LegendLine]
        let badge: CGRect?
        let number: String?
        let height: CGFloat
    }

    /// The legend. Wide, under a photograph, it has two columns: where and what on the left,
    /// which photograph and when on the right, set flush right against the frame and as wide as
    /// its longest line, so a file name is never cut. Narrow, beside a tall photograph, the two
    /// stack.
    private static func legend(_ sheet: Sheet, _ card: AnnexContent.Card, width: CGFloat) -> Legend {
        let split = width >= 800
        let metaWidth = split ? min(width * 0.45, (card.meta.map { sheet.small.width($0) }.max() ?? 0) + 2) : width
        let mainWidth = split ? width - metaWidth - 40 : width
        var lines: [LegendLine] = []
        var y: CGFloat = 0
        func add(_ text: String, _ ink: Ink, x: CGFloat, lineWidth: CGFloat, flushRight: Bool = false) {
            for line in sheet.wrapLines(text, ink, lineWidth) {
                y += ink.size
                lines.append(LegendLine(text: line, ink: ink, x: flushRight ? width - ink.width(line) : x, baseline: y))
                y += 8
            }
        }
        add(card.where.uppercased(), sheet.legendLabel, x: 0, lineWidth: mainWidth)
        y += 10
        // The finding's number in a dark badge, its words beside it in bold: the way it reads in the body.
        let number = card.number.map { String($0) }
        let badgeWidth = number.map { sheet.badgeText.width($0) + 24 } ?? 0
        let indent: CGFloat = number != nil ? badgeWidth + 14 : 0
        let titleTop = lines.count
        add(card.title, sheet.strong, x: indent, lineWidth: mainWidth - indent)
        let badge: CGRect? = number.map { _ in
            let baseline = lines[titleTop].baseline
            return CGRect(x: 0, y: baseline - sheet.strong.size - 3, width: badgeWidth, height: sheet.strong.size + 12)
        }
        if !card.context.isEmpty { y += 4 }
        for line in card.context { add(line, sheet.body, x: 0, lineWidth: mainWidth) }
        let main = y
        y = split ? 0 : y + 10
        for line in card.meta { add(line, sheet.small, x: 0, lineWidth: metaWidth, flushRight: split) }
        return Legend(lines: lines, badge: badge, number: number, height: max(main, y) - 8)
    }

    /// Draws `legend` with its top left corner at `left`, `top`.
    private static func drawLegend(_ sheet: Sheet, _ legend: Legend, left: CGFloat, top: CGFloat) {
        if let badge = legend.badge {
            let box = badge.offsetBy(dx: left, dy: top)
            sheet.fill(box, radius: 8, sheet.heavyRuleColour)
            let number = legend.number ?? ""
            sheet.text(number, box.midX - sheet.badgeText.width(number) / 2, box.maxY - 11, sheet.badgeText)
        }
        for line in legend.lines { sheet.text(line.text, left + line.x, top + line.baseline, line.ink) }
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
    private static func layout(_ sheet: Sheet, _ card: AnnexContent.Card, _ photoDir: URL) -> CardLayout? {
        guard let size = PhotoDecode.uprightSize(photoDir.appendingPathComponent(card.file)) else { return nil }
        let fit = AnnexPlate.fit(size.width, size.height)
        let inner = pageWidth - 2 * margin - 2 * framePad
        let besideWidth = inner - fit.boxWidth - legendGap
        var beside = besideWidth >= legendMin
        var legend = legend(sheet, card, width: beside ? besideWidth : inner)
        if beside, legend.height > fit.boxHeight + 200 {
            beside = false
            legend = self.legend(sheet, card, width: inner)
        }
        let body = beside ? max(fit.boxHeight, legend.height) : fit.boxHeight + 28 + legend.height
        let height = 2 * framePad + body
        return CardLayout(card: card, fit: fit, legend: legend, beside: beside, height: height, fits: height <= pageHeight - foot - 30 - margin)
    }

    /// One framed card, its top at `top`.
    private static func drawCard(_ sheet: Sheet, _ layout: CardLayout, top: CGFloat, _ photoDir: URL, measuring: Bool) {
        sheet.suppressHTML = true
        defer { sheet.suppressHTML = false }
        let inner = pageWidth - 2 * margin - 2 * framePad
        let fit = layout.fit
        let left = layout.beside ? margin + framePad : margin + framePad + (inner - fit.boxWidth) / 2
        let photo = CGRect(x: left, y: top + framePad, width: fit.boxWidth, height: fit.boxHeight)
        sheet.stroke(CGRect(x: margin, y: top, width: pageWidth - 2 * margin, height: layout.height), radius: 12, sheet.frameColour, 2)
        if !measuring { plate(sheet, layout.card, photoDir.appendingPathComponent(layout.card.file), fit, photo) }
        sheet.stroke(photo, radius: 0, sheet.hairlineColour, 1)
        if layout.beside {
            drawLegend(sheet, layout.legend, left: photo.maxX + legendGap, top: photo.minY)
        } else {
            sheet.line(margin + framePad, photo.maxY + 14, pageWidth - margin - framePad, photo.maxY + 14, sheet.ruleColour, 1.5)
            drawLegend(sheet, layout.legend, left: margin + framePad, top: photo.maxY + 28)
        }
    }

    /// A card whose legend is longer than a page: the framed photograph, then the legend running on.
    private static func drawRunOn(_ sheet: Sheet, _ layout: CardLayout, _ photoDir: URL, measuring: Bool) {
        sheet.suppressHTML = true
        defer { sheet.suppressHTML = false }
        let inner = pageWidth - 2 * margin - 2 * framePad
        let fit = layout.fit
        sheet.ensure(2 * framePad + fit.boxHeight)
        let top = sheet.y
        let left = margin + framePad + (inner - fit.boxWidth) / 2
        let photo = CGRect(x: left, y: top + framePad, width: fit.boxWidth, height: fit.boxHeight)
        sheet.stroke(CGRect(x: margin, y: top, width: pageWidth - 2 * margin, height: photo.maxY + framePad - top), radius: 12, sheet.frameColour, 2)
        if !measuring { plate(sheet, layout.card, photoDir.appendingPathComponent(layout.card.file), fit, photo) }
        sheet.stroke(photo, radius: 0, sheet.hairlineColour, 1)
        sheet.y = photo.maxY + framePad + 16
        let flowing = legend(sheet, layout.card, width: 600)
        for line in flowing.lines {
            sheet.ensure(line.ink.size + 10)
            sheet.text(line.text, margin + framePad + line.x, sheet.y + line.ink.size, line.ink)
            sheet.y += line.ink.size + 8
        }
        sheet.y += cardGap
    }

    /// The photograph itself: decoded upright at its plate size, laid on white when it carries
    /// alpha, written once as a JPEG into the spool, and drawn from that file so the PDF holds
    /// the same bytes the HTML copy embeds.
    private static func plate(_ sheet: Sheet, _ card: AnnexContent.Card, _ file: URL, _ fit: AnnexPlate.Fit, _ box: CGRect) {
        guard let spool = sheet.spool else { sheet.renderingFailed = true; return }
        let jpeg = spool.appendingPathComponent("plate-\(sheet.plateCount).jpg")
        sheet.plateCount += 1
        // One pool per plate: ImageIO hands back autoreleased buffers the size of the whole
        // photograph, and the export runs on the main actor, whose pool drains only when the
        // export returns. Without this, thirty 12-megapixel photographs held 1.2 GB at the peak.
        let written = autoreleasepool { () -> Bool in
            guard let decoded = PhotoDecode.uprightAtSize(file, width: fit.pixelWidth, height: fit.pixelHeight),
                  let picture = onPaper(decoded) else { return false }
            // No metadata and no orientation tag: the pixels are already upright, and a plate
            // carries nothing but the picture.
            guard let destination = CGImageDestinationCreateWithURL(jpeg as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
            CGImageDestinationAddImage(destination, picture, [kCGImageDestinationLossyCompressionQuality: AnnexPlate.jpegQuality] as CFDictionary)
            return CGImageDestinationFinalize(destination)
        }
        guard written else { sheet.renderingFailed = true; return }
        sheet.plate(jpeg, in: box, card: card)
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
