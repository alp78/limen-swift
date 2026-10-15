import LimenKit
import XCTest

/// Every launch names the separate Debug audit bundle. Fixtures and camera permission resets
/// cannot target the production bundle, even if a caller chooses the wrong build configuration.
@MainActor
final class RuntimeBoundaryTests: XCTestCase {
    private let s = Str(.en)
    private let gateLabel = "Lock the library and settings; keep the current handover available"

    override func setUp() { continueAfterFailure = false }

    #if targetEnvironment(simulator)
    func testSimulatorCameraRefusalPreservesDraft() {
        let app = auditApp()
        app.resetAuthorizationStatus(for: .camera)
        launchDemo(app)
        openRoom(app, name: "Camera boundary room")
        tap(app, s.photo)
        if app.staticTexts[s.cameraOpenFailed].waitForExistence(timeout: 3) {
            screenshot(app, "runtime-camera-unavailable-simulator")
            app.buttons[s.done].tap()
        } else {
            // Newer simulator runtimes can expose a camera source. Exercise their real
            // permission response instead of claiming that they followed the unavailable path.
            denyCameraPermission(app, screenshotName: "runtime-camera-denied-simulator")
        }
        XCTAssertTrue(app.buttons[s.gallery].exists)
        relaunchPreservingDraft(app)
        XCTAssertEqual(app.textFields[s.roomName].value as? String, "Camera boundary room")
    }

    func testUnsuccessfulAuthenticationDoesNotPersistALibraryGate() {
        let app = launchDemo()
        tap(app, s.back)
        tap(app, s.dataAndPrivacy)
        let toggle = app.switches[gateLabel]
        reveal(app, toggle)
        assertOff(toggle)
        toggle.tap()
        if app.buttons[s.done].waitForExistence(timeout: 3) {
            screenshot(app, "runtime-library-auth-unavailable")
        } else {
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let cancellation = NSPredicate(format: "label ==[c] %@", "Cancel")
            let systemCancel = springboard.buttons.matching(cancellation).firstMatch
            let appCancel = app.buttons.matching(cancellation).firstMatch
            let cancel = systemCancel.waitForExistence(timeout: 5) ? systemCancel : appCancel
            XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Available authentication must offer cancellation before enabling the gate")
            cancel.tap()
            XCTAssertTrue(app.buttons[s.done].waitForExistence(timeout: 10), "Cancelled authentication must leave a dismissible explanation")
            screenshot(app, "runtime-library-auth-cancelled")
        }
        app.buttons[s.done].tap()
        assertOff(toggle)
        relaunchPreservingDraft(app)
        tap(app, s.dataAndPrivacy)
        reveal(app, toggle)
        assertOff(toggle)
        tap(app, s.back)
        tap(app, s.allSessions)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Test street 1")).firstMatch.waitForExistence(timeout: 10), "A failed enable attempt must leave the saved library reachable")
    }
    #else
    func testCameraPermissionDenialOffersSettingsAndPreservesDraft() {
        let app = auditApp()
        app.resetAuthorizationStatus(for: .camera)
        launchDemo(app)
        openRoom(app, name: "Camera boundary room")
        tap(app, s.photo)
        denyCameraPermission(app, screenshotName: "runtime-camera-denied-physical")
        XCTAssertTrue(app.buttons[s.gallery].exists)
        XCTAssertEqual(app.textFields[s.roomName].value as? String, "Camera boundary room")
        relaunchPreservingDraft(app)
        XCTAssertEqual(app.textFields[s.roomName].value as? String, "Camera boundary room")
    }
    #endif

    private func denyCameraPermission(_ app: XCUIApplication, screenshotName: String) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow", "Ne pas autoriser", "Nicht erlauben", "Non consentire"])).firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 15), "The device must present its real camera consent dialog after the audit app permission reset")
        deny.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.buttons["Open Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts["Camera access is off. Allow it in Settings to take a photo, or choose a picture from Photos."].exists)
        screenshot(app, screenshotName)
        alert.buttons[s.cancel].tap()
    }

    func testSupportingDocumentPickerCancellationPreservesDraft() {
        let app = launchDemo()
        tap(app, s.stepDossier)
        replace(app, s.address, "Files boundary address")
        let documents = app.buttons["\(s.attachments) (0)"]
        reveal(app, documents)
        XCTAssertTrue(documents.exists)
        documents.tap()
        replace(app, "Document title", "Cancelled document draft")
        tap(app, s.addDocument)
        let cancel = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Cancel")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "The system Files picker must be presented")
        screenshot(app, "runtime-files-picker-before-cancel")
        cancel.tap()
        XCTAssertTrue(app.buttons[s.addDocument].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["Document title"].value as? String, "Cancelled document draft")
        XCTAssertTrue(documents.exists, "Cancellation must not add an attachment")
        XCTAssertFalse(app.buttons[s.done].exists, "Ordinary cancellation must not be reported as an import error")
        screenshot(app, "runtime-files-picker-cancelled")
        relaunchPreservingDraft(app)
        let address = app.textFields[s.address]
        reveal(app, address)
        XCTAssertEqual(address.value as? String, "Files boundary address")
        reveal(app, documents)
        XCTAssertTrue(documents.exists)
    }

    private func auditApp() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.peringer.limen.audit")
        app.launchEnvironment["LIMEN_LANG"] = "En"
        return app
    }

    @discardableResult
    private func launchDemo(_ supplied: XCUIApplication? = nil) -> XCUIApplication {
        let app = supplied ?? auditApp()
        app.launchArguments = ["LIMEN_DEMO", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", s.stepInspection)).firstMatch.waitForExistence(timeout: 30))
        return app
    }

    private func openRoom(_ app: XCUIApplication, name: String) {
        tap(app, s.stepInspection)
        let room = app.buttons[s.room(.room)]
        reveal(app, room)
        XCTAssertTrue(room.exists)
        room.tap()
        replace(app, s.roomName, name)
    }

    private func relaunchPreservingDraft(_ app: XCUIApplication) {
        // A simulated Home press is ignored by this physical XCTest runtime. Activating the
        // system Settings app creates an observable real interruption without changing settings.
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        XCTAssertTrue(settings.navigationBars.firstMatch.waitForExistence(timeout: 10), "The interruption must show the system Settings app")
        print("LIMEN_BACKGROUND_STATE audit=\(app.state.rawValue) settings=\(settings.state.rawValue)")
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    }

    private func assertOff(_ toggle: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(["0", s.no].contains(toggle.value as? String ?? ""), "Library gate must remain off", file: file, line: line)
    }

    private func replace(_ app: XCUIApplication, _ label: String, _ value: String) {
        let field = app.textFields[label].firstMatch
        reveal(app, field)
        XCTAssertTrue(field.exists, label)
        field.tap()
        let previous = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value)
        let done = app.keyboards.buttons["Done"]
        if done.exists && done.isHittable { done.tap() } else if app.keyboards.firstMatch.exists { app.scrollViews.firstMatch.swipeDown(velocity: .slow) }
    }

    private func tap(_ app: XCUIApplication, _ label: String) {
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
        if label != s.back { reveal(app, button) }
        XCTAssertTrue(button.exists, label)
        button.tap()
    }

    private func reveal(_ app: XCUIApplication, _ target: XCUIElement) {
        for _ in 0..<30 {
            if target.exists {
                let frame = target.frame
                let top = app.frame.minY + 140
                let bottom = app.frame.maxY - 60
                if target.isHittable && frame.midY >= top && frame.midY <= bottom { return }
                if frame.midY < top { app.swipeDown(velocity: .slow); continue }
            }
            app.swipeUp(velocity: .slow)
        }
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("LIMEN_RUNTIME_TREE \(name)\n\(app.debugDescription)")
    }
}

/// Run explicitly against an already installed, verified IPA. No fixture, reset, permission,
/// preference or record mutations are allowed in this production smoke.
@MainActor
final class InstalledReleaseSmokeTest: XCTestCase {
    func testInstalledReleaseReadOnlyFlow() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LIMEN_RELEASE_SMOKE"] == "1", "Requires explicit installed-release smoke opt-in")
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "dev.peringer.limen")
        app.activate()
        let startLabels = Lang.allCases.map { Str($0).startNewSession }
        let start = app.buttons.matching(NSPredicate(format: "label IN %@", startLabels)).firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 20), "Leave an existing open handover untouched; this smoke requires the landing screen")
        let lang = try XCTUnwrap(Lang.allCases.first { Str($0).startNewSession == start.label })
        let s = Str(lang)
        capture("release-landing")
        start.tap()
        XCTAssertTrue(app.textFields[s.firstName].waitForExistence(timeout: 10))
        capture("release-empty-form")
        app.buttons[s.back].firstMatch.tap()
        app.buttons[s.dataAndPrivacy].tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 10))
        capture("release-privacy")
        app.buttons[s.back].firstMatch.tap()
        XCTAssertTrue(app.buttons[s.allSessions].waitForExistence(timeout: 10))
        capture("release-returned-home")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
