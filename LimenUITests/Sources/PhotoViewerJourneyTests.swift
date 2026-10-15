import LimenKit
import XCTest

/// Explicitly opt in after tools/fixtures/photo-viewer.py seeds the simulator's separate audit
/// container. Ordinary AllTests runs do not require or create these preloaded visual fixtures.
@MainActor
final class PhotoViewerJourneyTests: XCTestCase {
    private let s = Str(.en)
    private let imageName = "synthetic-grid.png"

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIMEN_PHOTO_FIXTURE"] == "1", "Requires the explicit synthetic audit-container fixture")
        #if !targetEnvironment(simulator)
        throw XCTSkip("The host fixture seeder only accepts a simulator audit container")
        #endif
        XCUIDevice.shared.orientation = .portrait
    }

    func testDraftPhotoOpensZoomsResetsAndClosesWithoutDeletion() {
        let app = launch("photo-viewer-draft")
        let thumbnail = app.buttons["\(s.open) · \(imageName)"]
        reveal(app, thumbnail)
        let deletion = app.buttons[s.delete].firstMatch
        XCTAssertTrue(deletion.waitForExistence(timeout: 5))
        XCTAssertFalse(thumbnail.frame.intersects(deletion.frame), "Opening and deleting must have separate targets")
        capture(app, "photo-draft-separate-open-delete")
        exerciseViewer(app, thumbnail: thumbnail, name: "draft")
        XCTAssertTrue(thumbnail.exists, "Closing the viewer must retain its evidence")
        app.terminate()
        app.launch()
        reveal(app, thumbnail)
        XCTAssertTrue(thumbnail.exists, "The image must still be present after relaunch")
    }

    func testFinalizedPhotoIsViewableWithoutEditingOrDeletion() {
        let app = launch("photo-viewer-final")
        let thumbnail = app.buttons["\(s.open) · \(imageName)"]
        reveal(app, thumbnail)
        XCTAssertFalse(app.textFields[s.roomName].exists, "The finalized room name must be read only")
        XCTAssertFalse(app.buttons[s.delete].exists)
        XCTAssertFalse(app.buttons[s.gallery].exists)
        capture(app, "photo-finalized-read-only")
        exerciseViewer(app, thumbnail: thumbnail, name: "finalized")
        XCTAssertFalse(app.buttons[s.delete].exists)
    }

    func testExitBaselinePhotoUsesReadOnlyEntryEvidence() {
        let app = launch("photo-viewer-exit")
        let baseline = app.buttons[s.atEntry].firstMatch
        reveal(app, baseline)
        XCTAssertTrue(baseline.exists, "The exit must expose its saved entry baseline")
        baseline.tap()
        let thumbnail = app.buttons["\(s.open) · \(imageName)"]
        reveal(app, thumbnail)
        XCTAssertTrue(app.textFields[s.roomName].exists, "The current exit remains editable")
        XCTAssertFalse(app.buttons[s.delete].exists, "Entry evidence must not gain deletion controls in a mutable exit")
        capture(app, "photo-exit-baseline-read-only")
        exerciseViewer(app, thumbnail: thumbnail, name: "baseline")
        XCTAssertFalse(app.buttons[s.delete].exists)
    }

    private func launch(_ id: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.peringer.limen.audit")
        // Standard UserDefaults argument-domain overrides select only the synthetic record;
        // they neither reset the container nor require a production fixture hook.
        app.launchArguments = ["-openProtocol", id, "-openStep", "Inspection", "-openRoom", "photo-room",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["LIMEN_LANG"] = "En"
        app.launch()
        XCTAssertTrue(app.staticTexts[s.overviewPhotos].waitForExistence(timeout: 20), "Seed the reserved audit fixture before running this opt-in test")
        return app
    }

    private func exerciseViewer(_ app: XCUIApplication, thumbnail: XCUIElement, name: String) {
        thumbnail.tap()
        XCTAssertTrue(app.staticTexts["Original evidence"].waitForExistence(timeout: 10))
        let fullImage = app.scrollViews[imageName].images.firstMatch
        XCTAssertTrue(fullImage.waitForExistence(timeout: 10), "The full image must actually decode")
        XCTAssertGreaterThan(fullImage.frame.width, 200)
        XCTAssertGreaterThan(fullImage.frame.height, 200)
        let increase = app.buttons[s.increase]
        let decrease = app.buttons[s.decrease]
        XCTAssertTrue(app.buttons["100%"].waitForExistence(timeout: 10))
        XCTAssertFalse(decrease.isEnabled)
        XCTAssertTrue(increase.isEnabled)
        // UIKit can retain the covered draft's accessibility element during a full-screen
        // presentation. Its deletion target must be unreachable from the viewer.
        XCTAssertFalse(app.buttons[s.delete].firstMatch.isHittable, "The full viewer is separate from evidence deletion")
        capture(app, "photo-\(name)-full-image-100")
        for amount in [200, 400, 800] {
            increase.tap()
            XCTAssertTrue(app.buttons["\(amount)%"].waitForExistence(timeout: 5))
        }
        XCTAssertFalse(increase.isEnabled, "Zoom must stop at eight times")
        XCTAssertTrue(decrease.isEnabled)
        capture(app, "photo-\(name)-zoom-800")
        decrease.tap()
        XCTAssertTrue(app.buttons["400%"].waitForExistence(timeout: 5))
        app.buttons["400%"].tap()
        XCTAssertTrue(app.buttons["100%"].waitForExistence(timeout: 5), "The percentage control must reset the image")
        XCTAssertFalse(decrease.isEnabled)
        capture(app, "photo-\(name)-reset-100")
        app.buttons[s.done].tap()
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 10))
    }

    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<16 {
            if element.exists {
                let frame = element.frame
                if element.isHittable && frame.minY >= app.frame.minY + 130 && frame.maxY <= app.frame.maxY - 25 { return }
                if frame.minY < app.frame.minY + 130 { app.swipeDown(velocity: .slow); continue }
            }
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("LIMEN_PHOTO_VIEWER_TREE \(name)\n\(app.debugDescription)")
    }
}
