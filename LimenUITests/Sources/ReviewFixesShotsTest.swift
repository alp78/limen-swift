import LimenKit
import XCTest

/// The screens the 1.2.7 fixes change, from the seeded draft: a meter reading given a time that
/// is not one, the hub naming that reading under the time issue while the object panel stays
/// quiet, the reading removed and offered back through the undo bar, and the review step
/// listing the readings the paper prints. One journey, so the same screenshots come off the
/// simulator and the iPhone.
@MainActor
final class ReviewFixesShotsTest: XCTestCase {
    private let s = Str(.en)

    override func setUp() { continueAfterFailure = false }

    func testTheHubNamesTheBadTimeAndARemovedReadingIsOfferedBack() {
        let app = XCUIApplication()
        app.launchArguments = ["LIMEN_DEMO", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["LIMEN_LANG"] = "En"
        app.launch()
        XCTAssertTrue(element(app, "INSPECTION").waitForExistence(timeout: 30))

        // A reading with a time that is not one.
        element(app, "DOSSIER").tap()
        XCTAssertTrue(element(app, "Parties").waitForExistence(timeout: 10))
        // The disclosure header is a button under the legacy attributes and a link under the
        // modern ones, so it is matched by its label whatever type the runtime computes.
        let meters = element(app, "\(s.meters) (")
        reveal(app, meters)
        meters.tap()
        let add = app.buttons["\(s.add) · \(s.meters)"]
        reveal(app, add)
        add.tap()
        // The last time field on the page is the reading's; the object's is the first.
        let times = app.textFields.matching(identifier: s.handoverTime)
        let time = times.element(boundBy: times.count - 1)
        reveal(app, time)
        time.tap()
        time.typeText("2599")
        shoot(app, "01-reading-with-a-bad-time")

        // The hub names the reading under the time issue. The object panel still shows on this
        // draft, for its unanswered canton-overlay checks, so it is not asserted away here.
        app.buttons[s.back].firstMatch.tap()
        XCTAssertTrue(element(app, s.stillMissing).waitForExistence(timeout: 15))
        // The hub lists one issue at a time with the rest behind a count; the time issue is not
        // the first on the seeded draft.
        let showAll = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^.+ \\([0-9]+\\)$")).firstMatch
        if showAll.waitForExistence(timeout: 3) {
            reveal(app, showAll)
            showAll.tap()
        }
        let issue = element(app, "\(s.finalizationIssue(.handoverTime)) · \(s.meters)")
        XCTAssertTrue(issue.waitForExistence(timeout: 15), "the time issue names the reading")
        reveal(app, issue)
        shoot(app, "02-hub-names-the-bad-time")

        // Removing the reading offers it back; undo puts it back.
        element(app, "DOSSIER").tap()
        XCTAssertTrue(element(app, "Parties").waitForExistence(timeout: 10))
        reveal(app, meters)
        meters.tap()
        // The reading's delete key is the last on the page: the panels below it are closed.
        let deleteKeys = app.buttons.matching(NSPredicate(format: "label == %@", s.delete))
        let delete = deleteKeys.element(boundBy: deleteKeys.count - 1)
        reveal(app, delete)
        delete.tap()
        XCTAssertTrue(element(app, s.removedForUndo(.reading)).waitForExistence(timeout: 10), "the undo bar names the reading")
        shoot(app, "03-undo-bar-reading")
        app.buttons[s.undo].tap()
        XCTAssertTrue(element(app, "\(s.meters) (1)").waitForExistence(timeout: 10), "undo puts the reading back")
        app.buttons[s.back].firstMatch.tap()

        // The review step lists what the paper prints after the dossier.
        XCTAssertTrue(element(app, s.hubRecordLead).waitForExistence(timeout: 10))
        element(app, s.hubRecordLead).tap()
        XCTAssertTrue(element(app, "Object").waitForExistence(timeout: 10))
        let readings = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "\(s.meterIdentifier):")).firstMatch
        reveal(app, readings)
        XCTAssertTrue(readings.exists, "the review step prints the reading as the paper does")
        shoot(app, "04-review-lists-the-readings")
    }

    private func element(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func reveal(_ app: XCUIApplication, _ target: XCUIElement) {
        for _ in 0..<30 {
            // The list, not the rail above it, which is a scroll view too.
            let scroller = app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height } ?? app.scrollViews.firstMatch
            let viewport = scroller.exists ? scroller.frame : app.frame
            var upwards = true
            // Nothing is asked of the element before it exists: the dossier is a lazy list, and
            // a panel far down it has no element at all until the list has been scrolled to it.
            if target.exists {
                let frame = target.frame
                let top = viewport.minY + (target.elementType == .textField ? min(55, viewport.height * 0.2) : 8)
                let bottom = viewport.maxY - 24
                if target.isHittable && frame.midY >= top && frame.midY <= bottom { return }
                upwards = frame.midY >= top
            }
            let surface = scroller.exists ? scroller : app
            let from = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.75 : 0.25))
            let to = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.25 : 0.75))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
