import Foundation
import Testing
import UIKit
@testable import LimenKit

/// The printed record's tokens: the app's own sizes carried onto the page at 1.6 units per
/// point, the grid A4 at 150 dpi, the colours the screen's, and the face the system's. The
/// Android suite asserts the same numbers, which is what makes the two documents one document.
@Suite struct PdfTokensTests {
    @Test func theScaleCarriesTheAppsTokensOntoThePage() {
        #expect(abs(PdfTokens.dp(15) - 24) < 0.0001)
        #expect(abs(PdfTokens.body - 24) < 0.0001)
        #expect(abs(PdfTokens.panelRadius - 19.2) < 0.0001)
        #expect(abs(PdfTokens.border - 2.4) < 0.0001)
        #expect(abs(PdfTokens.panelPad - 25.6) < 0.0001)
        #expect(abs(PdfTokens.display - 67.2) < 0.0001)
        #expect(abs(PdfTokens.labelSmall - 19.2) < 0.0001)
    }

    @Test func theGridIsA4AtOneHundredAndFiftyDpi() {
        #expect(PdfTokens.width == 1240)
        #expect(PdfTokens.height == 1754)
        // The annex's photograph width follows from the margins and the card padding.
        #expect(AnnexPlate.maxWidth == Double(PdfTokens.width - 2 * PdfTokens.margin - 2 * PdfTokens.framePad))
    }

    @Test func everyColourIsTheScreensColour() {
        #expect(PdfTokens.panel == LimenPalette.plateRaised)
        #expect(PdfTokens.input == LimenPalette.input)
        #expect(PdfTokens.edge == LimenPalette.plateEdge)
        #expect(PdfTokens.navy == LimenPalette.navy)
        #expect(PdfTokens.ink == LimenPalette.ink)
        #expect(PdfTokens.inkDim == LimenPalette.inkDim)
        #expect(PdfTokens.warning == LimenPalette.warning)
        #expect(PdfTokens.warningOutline == LimenPalette.warningOutline)
        #expect(PdfTokens.positive == LimenPalette.positive)
        #expect(PdfTokens.navy == 0x233350)
        #expect(PdfTokens.paper == 0xFFFFFF)
        // The two values the parity pass had left at their pre-audit numbers, now Android's.
        #expect(LimenPalette.warningOutline == 0x835000)
        #expect(LimenPalette.disabledInk == 0xA7ADB8)
    }

    @Test func theRecordIsSetInTheAppsFamilyAndNeverInAMonospace() {
        #expect(PdfTokens.family == UIFont.systemFont(ofSize: 10).familyName)
        #expect(!PdfTokens.family.lowercased().contains("mono"))
    }
}
