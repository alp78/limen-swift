import CoreGraphics
import Foundation
import UIKit

extension PdfExport {
    /// The text styles a block names, the theme's six and the three the screens set inline.
    enum Style {
        case display, title, bodyLarge, body, bodyMedium, strong, labelLarge, labelSmall, small
    }

    /// A face at a size in a colour, with its tracking: the Paint of the Android sheet. The
    /// tracking is the theme's letter spacing as an em fraction, which the kern takes in points.
    struct Face {
        let font: UIFont
        let colour: UIColor
        let track: CGFloat

        init(_ font: UIFont, _ colour: UIColor, track: CGFloat = 0) {
            self.font = font
            self.colour = colour
            self.track = track
        }

        var size: CGFloat { font.pointSize }

        var attributes: [NSAttributedString.Key: Any] {
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
            if track != 0 { attributes[.kern] = track * size }
            return attributes
        }

        func width(_ text: String) -> CGFloat {
            (text as NSString).size(withAttributes: attributes).width
        }

        /// The baseline that centres this face in a line `line` tall, the same in both passes:
        /// Android's `(line - (descent - ascent)) / 2 - ascent` with UIKit's signs, where the
        /// ascender is positive and the descender negative.
        func baseline(_ line: CGFloat) -> CGFloat {
            (line - (font.ascender - font.descender)) / 2 + font.ascender
        }

        func tinted(_ colour: UIColor) -> Face { Face(font, colour, track: track) }
        func tinted(_ rgb: UInt32) -> Face { Face(font, UIColor(rgb: rgb), track: track) }
    }

    /// One set of faces and fills per drawing pass: three weights of the system face, which is
    /// the family the app renders, and the flat fills and strokes of its panels. Core Graphics
    /// subsets each face into the file. No monospace: the screens use it for a readout or two,
    /// the paper for nothing.
    final class Paints {
        private static func face(_ size: CGFloat, _ weight: UIFont.Weight, _ colour: UInt32, track: CGFloat = 0) -> Face {
            Face(.systemFont(ofSize: size, weight: weight), UIColor(rgb: colour), track: track)
        }

        let display = Paints.face(PdfTokens.display, .bold, PdfTokens.paper, track: PdfTokens.displayTrack)
        let title = Paints.face(PdfTokens.title, .bold, PdfTokens.ink)
        let bodyLarge = Paints.face(PdfTokens.bodyLarge, .regular, PdfTokens.ink)
        let body = Paints.face(PdfTokens.body, .regular, PdfTokens.ink)
        let bodyMedium = Paints.face(PdfTokens.body, .medium, PdfTokens.ink)
        /// A finding's words in the annex legend, as the body sets them in bold.
        let strong = Paints.face(PdfTokens.bodyLarge, .bold, PdfTokens.ink)
        let labelLarge = Paints.face(PdfTokens.labelLarge, .bold, PdfTokens.ink, track: PdfTokens.labelLargeTrack)
        let labelSmall = Paints.face(PdfTokens.labelSmall, .medium, PdfTokens.inkDim, track: PdfTokens.labelSmallTrack)
        let small = Paints.face(PdfTokens.labelSmall, .regular, PdfTokens.inkDim)
        /// The finding number inside its navy badge.
        let badge = Paints.face(PdfTokens.labelLarge, .bold, PdfTokens.paper)
        let chip = Paints.face(PdfTokens.labelSmall, .medium, PdfTokens.ink, track: PdfTokens.chipTrack)
        let chipActive = Paints.face(PdfTokens.labelSmall, .medium, PdfTokens.paper, track: PdfTokens.chipTrack)
        let pillSeal = Paints.face(PdfTokens.labelLarge, .bold, PdfTokens.paper, track: PdfTokens.labelLargeTrack)
        let pillWarning = Paints.face(PdfTokens.labelLarge, .bold, PdfTokens.warningOutline, track: PdfTokens.labelLargeTrack)
        let pillDim = Paints.face(PdfTokens.labelLarge, .bold, PdfTokens.inkDim, track: PdfTokens.labelLargeTrack)
        let pillPaper = Paints.face(PdfTokens.labelLarge, .bold, PdfTokens.navy, track: PdfTokens.labelLargeTrack)

        let paperFill = UIColor(rgb: PdfTokens.paper)
        let panelFill = UIColor(rgb: PdfTokens.panel)
        let warningFill = UIColor(rgb: PdfTokens.warning)
        let inputFill = UIColor(rgb: PdfTokens.input)
        let navyFill = UIColor(rgb: PdfTokens.navy)
        /// The navy stroke and rule are the border width; the edge stroke is 1 and the edge rule 1.5.
        let navy = UIColor(rgb: PdfTokens.navy)
        let warningOutline = UIColor(rgb: PdfTokens.warningOutline)
        let edge = UIColor(rgb: PdfTokens.edge)

        func of(_ style: Style) -> Face {
            switch style {
            case .display: return display
            case .title: return title
            case .bodyLarge: return bodyLarge
            case .body: return body
            case .bodyMedium: return bodyMedium
            case .strong: return strong
            case .labelLarge: return labelLarge
            case .labelSmall: return labelSmall
            case .small: return small
            }
        }

        /// The theme's line height where it sets one, else the face's natural line.
        func line(of style: Style) -> CGFloat {
            switch style {
            case .body, .bodyMedium: return PdfTokens.bodyLine
            case .bodyLarge, .strong: return PdfTokens.bodyLargeLine
            default: return of(style).size * PdfTokens.line
            }
        }
    }
}

extension UIColor {
    /// A palette value as a colour: the same hex the SwiftUI theme reads, opaque.
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
