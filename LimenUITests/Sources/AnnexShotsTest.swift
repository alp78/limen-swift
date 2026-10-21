import LimenKit
import XCTest

/// The document as the phone shows it: the record `MeasurementTests` left in the audit store,
/// opened from the records list to its document, and the preview paged down from the cover
/// through the room panels and the signatures into the annex, with a screenshot every other
/// swipe. Skipped when that record is not in the store, so the suite stays green on a fresh
/// simulator.
@MainActor
final class AnnexShotsTest: XCTestCase {
    private let s = Str(.fr)

    override func setUp() { continueAfterFailure = false }

    func testTheMeasurementRecordsAnnexOnThePreview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["LIMEN_LANG"] = "Fr"
        app.launch()
        // The app reopens where it was left, which after a measurement run is the record or its
        // document; the way back to the landing is the back key, as on every screen.
        let landing = app.buttons[s.startNewSession]
        for _ in 0..<6 where !landing.waitForExistence(timeout: 5) {
            let done = app.navigationBars.buttons[s.done].firstMatch
            if done.exists { done.tap(); continue }
            let back = app.buttons[s.back].firstMatch
            if back.exists { back.tap() }
        }
        XCTAssertTrue(landing.waitForExistence(timeout: 30), "the landing")
        app.buttons[s.allSessions].tap()
        // The list groups records under a header that repeats the address, so the card is the
        // button carrying it, not the first text that does.
        let card = key(app, "Avenue de la Mesure 30")
        try XCTSkipUnless(card.waitForExistence(timeout: 15), "the measurement record is not in this store")
        card.tap()
        let door = key(app, s.hubRecordLead)
        XCTAssertTrue(door.waitForExistence(timeout: 30), "the record opens on its hub")
        door.tap()
        // A finalized record offers its document through the export, as the parity journeys
        // open it: EXPORTER LE PDF, then Ouvrir on the retained copy, which is Quick Look.
        let export = app.buttons[s.exportPdf]
        XCTAssertTrue(export.waitForExistence(timeout: 30), "the export key")
        export.tap()
        let open = app.buttons[s.open].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 120), "the export finished and offers Ouvrir")
        reveal(app, open)
        open.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 30), "the document opened")
        // Quick Look draws the pages without accessibility of their own, so the document is paged
        // by swiping and photographed as it goes; the pages that matter are picked out afterwards.
        sleep(4)
        shoot(app, "annex-00")
        for swipe in 1...48 {
            app.swipeUp()
            if swipe.isMultiple(of: 2) { shoot(app, String(format: "annex-%02d", swipe)) }
        }
    }

    private func key(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func element(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func reveal(_ app: XCUIApplication, _ target: XCUIElement) {
        for _ in 0..<30 {
            if target.exists && target.isHittable { return }
            let scroller = app.scrollViews.firstMatch
            let surface = scroller.exists ? scroller : app
            surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        }
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
