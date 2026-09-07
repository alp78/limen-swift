import XCTest

/// The walk the Android instrumentation takes: the landing, the new-session form with its three
/// actors and two kinds, the data and privacy page with its licence notice and backup dialog, then
/// a seeded draft through inspection, objects, dossier, the canton grid, review and the signatures,
/// with a screenshot of each written to the folder named in LIMEN_SHOTS.
///
/// Text inside a SwiftUI button is folded into the button's own label, so the keys and rows are
/// found by the words their labels contain rather than as static texts.
final class SmokeTest: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["LIMEN_SHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
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
        XCTAssertTrue(app.buttons["NEW SESSION"].waitForExistence(timeout: 30))
        shoot(app, "01-landing")

        app.buttons["NEW SESSION"].tap()
        XCTAssertTrue(app.buttons["Tenant"].waitForExistence(timeout: 10))
        app.buttons["Landlord"].tap()
        app.buttons["Agency"].tap()
        XCTAssertTrue(element(app, "Agency name").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Entry"].exists)
        app.buttons["Exit"].tap()
        app.buttons["Entry"].tap()
        shoot(app, "02-new-session")
        app.buttons["BACK"].firstMatch.tap()

        XCTAssertTrue(app.buttons["DATA, BACKUP & PRIVACY"].waitForExistence(timeout: 10))
        app.buttons["DATA, BACKUP & PRIVACY"].tap()
        XCTAssertTrue(element(app, "Privacy information").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "Responsible data controller").exists)
        shoot(app, "03-privacy")
        app.swipeUp()

        // The notice reached the bundle: a build that dropped it shows the missing line instead.
        XCTAssertTrue(app.buttons["LICENCES"].waitForExistence(timeout: 5))
        app.buttons["LICENCES"].tap()
        XCTAssertTrue(element(app, "Cantonal flags of Switzerland").waitForExistence(timeout: 10))
        shoot(app, "04-licences")
        app.buttons["BACK"].firstMatch.tap()
        XCTAssertTrue(element(app, "Privacy information").waitForExistence(timeout: 10))
        app.swipeUp()

        XCTAssertTrue(app.buttons["CREATE BACKUP"].waitForExistence(timeout: 5))
        app.buttons["CREATE BACKUP"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        shoot(app, "05-backup-password")

        // Both fields empty is a valid backup, and the screen has to say so: the whole point of
        // making the password optional is that an unprotected archive announces itself.
        app.alerts.buttons["CREATE BACKUP"].tap()
        XCTAssertTrue(element(app, "without a password").waitForExistence(timeout: 30))
        app.swipeUp()
        shoot(app, "06-backup-unprotected")

        app.buttons["BACK"].firstMatch.tap()
        XCTAssertTrue(app.buttons["NEW SESSION"].waitForExistence(timeout: 10))
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
        app.buttons["BACK"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Room"].waitForExistence(timeout: 10))
        app.buttons["BACK"].firstMatch.tap()
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
        app.buttons["BACK"].firstMatch.tap()
        XCTAssertTrue(app.buttons["CLOSE THE RECORD"].waitForExistence(timeout: 10))
        app.buttons["CLOSE THE RECORD"].tap()
        XCTAssertTrue(element(app, "Object").waitForExistence(timeout: 10))
        shoot(app, "13-review")
        app.swipeUp()
        XCTAssertTrue(app.buttons["SIGNATURES"].waitForExistence(timeout: 5))
        app.buttons["SIGNATURES"].tap()
        XCTAssertTrue(element(app, "Unilateral record").waitForExistence(timeout: 10))
        shoot(app, "14-sign")
        app.buttons["SIGN"].firstMatch.tap()
        XCTAssertTrue(element(app, "Signature drawing area").waitForExistence(timeout: 10))
        let pad = element(app, "Signature drawing area")
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.1, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)))
        shoot(app, "15-ink")
        app.buttons["KEEP"].tap()
        XCTAssertTrue(element(app, "Signed").waitForExistence(timeout: 10))
        shoot(app, "16-signed")
        app.buttons["BACK"].firstMatch.tap()
        app.buttons["BACK"].firstMatch.tap()
        app.buttons["BACK"].firstMatch.tap()
        XCTAssertTrue(app.buttons["NEW SESSION"].waitForExistence(timeout: 10))
    }
}
