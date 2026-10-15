import LimenKit
import XCTest

/// The walk the Android instrumentation takes: the landing, the new-session form with its three
/// actors and two kinds, the data and privacy page with its licence notice and backup dialog, then
/// a seeded draft through inspection, objects, dossier, the canton grid, review and the signatures,
/// with a screenshot of each written to the folder named in LIMEN_SHOTS.
///
/// Text inside a SwiftUI button is folded into the button's own label, so the keys and rows are
/// found by the words their labels contain rather than as static texts.
@MainActor
final class SmokeTest: XCTestCase {
    private let s = Str(.en)
    override func setUp() {
        continueAfterFailure = false
    }

    private func shoot(_ app: XCUIApplication, _ name: String, wholeScreen: Bool = false) {
        // The screen, not the app, for a shot taken after a rotation: the app's buffer can still be
        // the portrait one for a moment, sideways with a black half, while the screen's is upright.
        let screenshot = wholeScreen ? XCUIScreen.main.screenshot() : app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["LIMEN_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
        }
    }

    private func reveal(_ app: XCUIApplication, _ target: XCUIElement) {
        for _ in 0..<30 {
            let scroller = app.scrollViews.firstMatch
            let viewport = scroller.exists && target.identifier != "start-session" ? scroller.frame : app.frame
            let top = viewport.minY + (target.elementType == .textField ? min(55, viewport.height * 0.2) : 8)
            let bottom = viewport.maxY - 24
            var upwards = true
            if target.exists {
                let frame = target.frame
                if target.isHittable && frame.midY >= top && frame.midY <= bottom { return }
                upwards = frame.midY >= top
            }
            let surface = scroller.exists ? scroller : app
            let from = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.75 : 0.25))
            let to = surface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: upwards ? 0.25 : 0.75))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
    }

    private func element(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["LIMEN_LANG"] = "En"
        app.launch()
        return app
    }

    func testTheLandingTheFormAndThePrivacyPage() {
        let app = launch(["LIMEN_RESET"])
        XCTAssertTrue(app.buttons[s.startNewSession].waitForExistence(timeout: 30))
        shoot(app, "01-landing")

        app.buttons[s.startNewSession].tap()
        XCTAssertTrue(app.buttons["Tenant"].waitForExistence(timeout: 10))
        app.buttons["Landlord"].tap()
        app.buttons["Agency"].tap()
        XCTAssertTrue(element(app, "Agency name").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Entry"].exists)
        app.buttons["Exit"].tap()
        app.buttons["Entry"].tap()
        shoot(app, "02-new-session")
        app.buttons[s.back].firstMatch.tap()

        XCTAssertTrue(app.buttons[s.dataAndPrivacy].waitForExistence(timeout: 10))
        app.buttons[s.dataAndPrivacy].tap()
        XCTAssertTrue(element(app, "Privacy information").waitForExistence(timeout: 10))
        reveal(app, element(app, "Responsible data controller"))
        shoot(app, "03-privacy")
        reveal(app, app.buttons["LICENCES"])

        // The notice reached the bundle: a build that dropped it shows the missing line instead.
        XCTAssertTrue(app.buttons["LICENCES"].waitForExistence(timeout: 5))
        app.buttons["LICENCES"].tap()
        XCTAssertTrue(element(app, "Cantonal flags of Switzerland").waitForExistence(timeout: 10))
        shoot(app, "04-licences")
        app.buttons[s.back].firstMatch.tap()
        XCTAssertTrue(element(app, "Privacy information").waitForExistence(timeout: 10))
        reveal(app, app.buttons[s.createBackup])

        XCTAssertTrue(app.buttons[s.createBackup].waitForExistence(timeout: 5))
        app.buttons[s.createBackup].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        shoot(app, "05-backup-password")

        XCTAssertFalse(app.alerts.buttons[s.createBackup].isEnabled)
        app.alerts.buttons[s.cancel].tap()
        let plain = app.buttons["Create unencrypted archive"]
        reveal(app, plain)
        plain.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons[s.yes].tap()
        XCTAssertTrue(element(app, "without a password").waitForExistence(timeout: 30))
        shoot(app, "06-backup-unprotected")

        app.buttons[s.back].firstMatch.tap()
        XCTAssertTrue(app.buttons[s.startNewSession].waitForExistence(timeout: 10))
    }

    func testTheSeededDraftWalksEveryStep() {
        let app = launch(["LIMEN_DEMO"])
        XCTAssertTrue(element(app, "INSPECTION").waitForExistence(timeout: 30))
        shoot(app, "07-hub")

        element(app, "INSPECTION").tap()
        XCTAssertTrue(app.buttons["Room"].waitForExistence(timeout: 10))
        shoot(app, "08-inspection")
        app.buttons["OBJECTS"].tap()
        XCTAssertTrue(element(app, "Add something else").waitForExistence(timeout: 10))
        shoot(app, "09-objects")
        // Back retraces the route rather than jumping to the hub: one press returns to the rooms,
        // the hub is one press further out.
        app.buttons[s.back].firstMatch.tap()
        XCTAssertTrue(app.buttons["Room"].waitForExistence(timeout: 10))
        app.buttons[s.back].firstMatch.tap()
        XCTAssertTrue(element(app, "DOSSIER").waitForExistence(timeout: 10))
        element(app, "DOSSIER").tap()
        XCTAssertTrue(element(app, "Parties").waitForExistence(timeout: 10))
        shoot(app, "10-dossier")
        let cantonKey = app.buttons["SELECT CANTON"]
        XCTAssertTrue(cantonKey.waitForExistence(timeout: 5))
        cantonKey.tap()
        XCTAssertTrue(app.buttons["ZH · Zürich"].waitForExistence(timeout: 10))
        shoot(app, "11-cantons")
        app.buttons["ZH · Zürich"].tap()
        XCTAssertTrue(element(app, "Required throughout the canton in the 2026 official snapshot").waitForExistence(timeout: 10))
        shoot(app, "12-legal-overlay")
        app.buttons[s.back].firstMatch.tap()
        XCTAssertTrue(element(app, s.hubRecordLead).waitForExistence(timeout: 10))
        element(app, s.hubRecordLead).tap()
        XCTAssertTrue(element(app, "Object").waitForExistence(timeout: 10))
        shoot(app, "13-review")
        let preview = app.buttons["preview-document"]
        reveal(app, preview)
        preview.tap()
        XCTAssertTrue(app.buttons["confirm-review"].waitForExistence(timeout: 30))
        app.buttons["confirm-review"].tap()
        reveal(app, app.buttons["SIGNATURES"])
        XCTAssertTrue(app.buttons["SIGNATURES"].waitForExistence(timeout: 5))
        app.buttons["SIGNATURES"].tap()
        XCTAssertTrue(element(app, "Unilateral record").waitForExistence(timeout: 10))
        shoot(app, "14-sign")
        reveal(app, app.buttons["SIGN"].firstMatch)
        app.buttons["SIGN"].firstMatch.tap()
        XCTAssertTrue(element(app, "Signature drawing area").waitForExistence(timeout: 10))
        let pad = element(app, "Signature drawing area")
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.1, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)))
        shoot(app, "15-ink")
        app.buttons[s.saveInk].tap()
        XCTAssertTrue(element(app, "Signed").waitForExistence(timeout: 10))
        shoot(app, "16-signed")

        // On its side the phone is wider than the readable column, so this is where the cap shows:
        // the plate spans the window and the content sits centred in 560 points of it.
        XCUIDevice.shared.orientation = .landscapeLeft
        let window = app.windows.firstMatch
        let turned = NSPredicate { _, _ in window.frame.width > window.frame.height }
        wait(for: [expectation(for: turned, evaluatedWith: nil)], timeout: 10)
        XCTAssertTrue(element(app, "Signed").waitForExistence(timeout: 10))
        shoot(app, "17-signed-landscape", wholeScreen: true)
        XCUIDevice.shared.orientation = .portrait
        let upright = NSPredicate { _, _ in window.frame.height > window.frame.width }
        wait(for: [expectation(for: upright, evaluatedWith: nil)], timeout: 10)
        app.buttons[s.back].firstMatch.tap()
        app.buttons[s.back].firstMatch.tap()
        app.buttons[s.back].firstMatch.tap()
        XCTAssertTrue(app.buttons[s.startNewSession].waitForExistence(timeout: 10))
    }
}
