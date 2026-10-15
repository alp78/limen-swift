import LimenKit
import XCTest

/// Starts from the empty isolated app and enters every fact used by the final document.
@MainActor
final class ParityJourneyTest: XCTestCase {
    private let s = Str(.en)

    override func setUp() { continueAfterFailure = false }

    func testEmptyFormToDrawnSignaturesAndOpenedDocument() {
        let app = XCUIApplication()
        app.launchArguments = ["LIMEN_RESET"]
        app.launchEnvironment["LIMEN_LANG"] = "En"
        app.launch()
        XCTAssertTrue(app.buttons[s.startNewSession].waitForExistence(timeout: 30))
        app.buttons[s.startNewSession].tap()
        fill(app, s.firstName, "Alex")
        fill(app, s.lastName, "Example")
        let start = app.buttons["start-session"]
        reveal(app, start)
        XCTAssertTrue(start.isEnabled)
        start.tap()
        tap(app, s.stepDossier)
        fill(app, s.address, "Auditstrasse 12")
        fill(app, s.place, "5000 Aarau")
        reveal(app, app.buttons[s.selectCanton])
        app.buttons[s.selectCanton].tap()
        app.buttons[s.canton(.ag)].tap()
        fill(app, s.handoverTime, "1030")
        dismissKeyboard(app)
        for requirement in [LegalRequirement.leaseAndLocalTiming, .initialRentForm] {
            let answer = app.buttons["legal-\(requirement.rawValue)-Confirmed"]
            reveal(app, answer)
            if answer.exists { answer.tap() }
            let note = app.textFields["legal-note-\(requirement.rawValue)"]
            if !note.waitForExistence(timeout: 2) { answer.tap() }
            XCTAssertTrue(note.waitForExistence(timeout: 5))
            fill(app, "legal-note-\(requirement.rawValue)", "Synthetic acceptance fixture; documents checked")
            dismissKeyboard(app)
        }
        fill(app, s.role(.landlord), "Case Owner")
        dismissKeyboard(app)
        let noKeys = app.buttons[s.keyTransfer(.noPhysicalKeys)]
        reveal(app, noKeys)
        noKeys.tap()
        app.buttons[s.back].firstMatch.tap()
        tap(app, s.stepInspection)
        let room = app.buttons[s.room(.kitchen)]
        reveal(app, room)
        room.tap()
        app.buttons[s.useSelectedRooms].tap()
        tap(app, s.room(.kitchen))
        tap(app, s.roomInspected)
        app.buttons[s.back].firstMatch.tap()
        app.buttons[s.back].firstMatch.tap()
        tap(app, s.hubClose)
        let preview = app.buttons["preview-document"]
        reveal(app, preview)
        preview.tap()
        XCTAssertTrue(app.buttons["confirm-review"].waitForExistence(timeout: 30))
        screenshot(app, "empty-journey-complete-draft")
        app.buttons["confirm-review"].tap()
        tap(app, s.stepSign)
        for _ in 0..<2 {
            let sign = app.buttons[s.signKey].firstMatch
            reveal(app, sign)
            XCTAssertTrue(sign.isEnabled)
            sign.tap()
            let pad = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", s.signaturePad)).firstMatch
            XCTAssertTrue(pad.waitForExistence(timeout: 10))
            pad.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.6)).press(forDuration: 0.1, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)))
            app.buttons[s.saveInk].tap()
        }
        let finalize = app.buttons[s.finalizeRecord].firstMatch
        reveal(app, finalize)
        screenshot(app, "empty-journey-signed")
        XCTAssertTrue(finalize.isEnabled)
        finalize.tap()
        let export = app.buttons[s.exportPdf]
        XCTAssertTrue(export.waitForExistence(timeout: 30))
        export.tap()
        let open = app.buttons[s.open].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        reveal(app, open)
        open.tap()
        screenshot(app, "empty-journey-opened-pdf")
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
    }

    func testAgencyStandaloneExitThenAmendment() {
        let app = startActorRecord(agency: true, kind: .exit)
        completeActorDossier(app, kind: .exit, agency: true, seeded: false)
        completeInspection(app, seeded: false)
        signFinalizeExport(app, tag: "agency-standalone-exit")
        let amend = app.buttons[s.amendRecord]
        reveal(app, amend)
        amend.tap()
        XCTAssertTrue(app.buttons[s.hubClose].waitForExistence(timeout: 30))
        tap(app, s.stepDossier)
        replace(app, s.handoverTime, "1130")
        dismissKeyboard(app)
        app.buttons[s.back].firstMatch.tap()
        signFinalizeExport(app, tag: "agency-amendment")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", s.pdfAmends)).firstMatch.exists)
    }

    func testPrivateLandlordEntryThenSeededExit() {
        let app = startActorRecord(agency: false, kind: .entry)
        completeActorDossier(app, kind: .entry, agency: false, seeded: false)
        completeInspection(app, seeded: false)
        signFinalizeExport(app, tag: "landlord-entry")
        let done = app.buttons[s.done].firstMatch
        reveal(app, done)
        done.tap()
        if !app.buttons[s.allSessions].exists { app.buttons[s.back].firstMatch.tap() }
        XCTAssertTrue(app.buttons[s.allSessions].waitForExistence(timeout: 15))
        app.buttons[s.allSessions].tap()
        let seed = app.buttons[s.exitFromThis].firstMatch
        XCTAssertTrue(seed.waitForExistence(timeout: 30))
        reveal(app, seed)
        seed.tap()
        let start = app.buttons["start-session"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        reveal(app, start)
        XCTAssertTrue(start.isEnabled)
        start.tap()
        completeActorDossier(app, kind: .exit, agency: false, seeded: true)
        completeInspection(app, seeded: true)
        signFinalizeExport(app, tag: "landlord-seeded-exit")
    }

    private func startActorRecord(agency: Bool, kind: Kind) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["LIMEN_RESET", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["LIMEN_LANG"] = "En"
        app.launch()
        XCTAssertTrue(app.buttons[s.startNewSession].waitForExistence(timeout: 30))
        app.buttons[s.startNewSession].tap()
        app.buttons[agency ? s.actorAgency : s.actorLandlordPrivate].tap()
        if kind == .exit { app.buttons[s.exit].tap() }
        if agency { fill(app, s.companyName, "Synthetic Agency") }
        fill(app, s.firstName, "Alex")
        fill(app, s.lastName, "Example")
        let start = app.buttons["start-session"]
        reveal(app, start)
        XCTAssertTrue(start.isEnabled)
        start.tap()
        return app
    }

    private func completeActorDossier(_ app: XCUIApplication, kind: Kind, agency: Bool, seeded: Bool) {
        tap(app, s.stepDossier)
        if !seeded {
            fill(app, s.address, "Auditstrasse 24")
            fill(app, s.place, "5000 Aarau")
            reveal(app, app.buttons[s.selectCanton])
            app.buttons[s.selectCanton].tap()
            app.buttons[s.canton(.ag)].tap()
        }
        fill(app, s.handoverTime, "1030")
        dismissKeyboard(app)
        let requirements: [LegalRequirement] = kind == .entry ? [.leaseAndLocalTiming, .initialRentForm] : [.leaseAndLocalTiming]
        for requirement in requirements {
            let answer = app.buttons["legal-\(requirement.rawValue)-Confirmed"]
            reveal(app, answer)
            answer.tap()
            let note = app.textFields["legal-note-\(requirement.rawValue)"]
            XCTAssertTrue(note.waitForExistence(timeout: 5))
            fill(app, "legal-note-\(requirement.rawValue)", "Synthetic UI acceptance; contract checked")
        }
        if !seeded {
            fill(app, s.role(.tenant), "Case Tenant")
            if agency {
                fill(app, s.role(.landlord), "Property Owner")
                fill(app, s.authority, "Synthetic written mandate for this handover")
            }
        }
        dismissKeyboard(app)
        let noKeys = app.buttons[s.keyTransfer(.noPhysicalKeys)]
        reveal(app, noKeys)
        noKeys.tap()
        app.buttons[s.back].firstMatch.tap()
    }

    private func completeInspection(_ app: XCUIApplication, seeded: Bool) {
        tap(app, s.stepInspection)
        if !seeded {
            let room = app.buttons[s.room(.kitchen)]
            reveal(app, room)
            room.tap()
            app.buttons[s.useSelectedRooms].tap()
        }
        tap(app, s.room(.kitchen))
        tap(app, s.roomInspected)
        if seeded {
            let baseline = app.buttons[s.atEntry].firstMatch
            reveal(app, baseline)
            XCTAssertTrue(baseline.exists)
            baseline.tap()
        }
        screenshot(app, seeded ? "entry-baseline-visible-in-fresh-exit" : "actor-room-inspected")
        app.buttons[s.back].firstMatch.tap()
        app.buttons[s.back].firstMatch.tap()
    }

    private func signFinalizeExport(_ app: XCUIApplication, tag: String) {
        tap(app, s.hubClose)
        let preview = app.buttons["preview-document"]
        reveal(app, preview)
        preview.tap()
        XCTAssertTrue(app.buttons["confirm-review"].waitForExistence(timeout: 30))
        screenshot(app, tag + "-full-preview")
        app.buttons["confirm-review"].tap()
        tap(app, s.stepSign)
        for _ in 0..<2 {
            let sign = app.buttons[s.signKey].firstMatch
            reveal(app, sign)
            XCTAssertTrue(sign.isEnabled)
            sign.tap()
            let pad = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", s.signaturePad)).firstMatch
            XCTAssertTrue(pad.waitForExistence(timeout: 10))
            pad.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.6)).press(forDuration: 0.1, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)))
            app.buttons[s.saveInk].tap()
        }
        let finalize = app.buttons[s.finalizeRecord].firstMatch
        reveal(app, finalize)
        screenshot(app, tag + "-signed")
        XCTAssertTrue(finalize.isEnabled)
        finalize.tap()
        let export = app.buttons[s.exportPdf]
        XCTAssertTrue(export.waitForExistence(timeout: 30))
        export.tap()
        let open = app.buttons[s.open].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 30))
        reveal(app, open)
        open.tap()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        screenshot(app, tag + "-opened-pdf")
        app.navigationBars.buttons[s.done].firstMatch.tap()
    }

    func testInvalidDateSurvivesRelaunchAndHasExplicitRevert() {
        let app = XCUIApplication()
        app.launchArguments = ["LIMEN_DEMO"]
        app.launchEnvironment["LIMEN_LANG"] = "En"
        app.launch()
        tap(app, s.stepDossier)
        replace(app, s.handoverDate, "31022026")
        dismissKeyboard(app)
        app.buttons[s.back].firstMatch.tap()
        app.terminate()
        app.launchArguments = []
        app.launch()
        tap(app, s.stepDossier)
        let date = app.textFields[s.handoverDate]
        reveal(app, date)
        XCTAssertEqual(date.value as? String, "31/02/2026")
        let revert = app.buttons["Restore previous valid value"]
        reveal(app, revert)
        XCTAssertTrue(revert.exists)
        revert.tap()
        XCTAssertNotEqual(date.value as? String, "31/02/2026")
        screenshot(app, "invalid-date-restored")
    }

    private func fill(_ app: XCUIApplication, _ label: String, _ text: String) {
        let field = app.textFields[label].firstMatch
        reveal(app, field)
        XCTAssertTrue(field.exists, label)
        field.tap()
        field.typeText(text)
        finishEditing(app, field)
    }

    // End editing the way a person does: the app's Done above a multi-line field, Return on a
    // single-line one. Looking for a keyboard key labelled "Done" depended on the runtime's own
    // labels and left the keyboard up on both installed runtimes.
    private func finishEditing(_ app: XCUIApplication, _ field: XCUIElement) {
        let done = app.buttons[s.done].firstMatch
        if done.exists && done.isHittable { done.tap() } else { field.typeText("\n") }
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }

    private func replace(_ app: XCUIApplication, _ label: String, _ text: String) {
        let field = app.textFields[label].firstMatch
        reveal(app, field)
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    private func tap(_ app: XCUIApplication, _ label: String) {
        let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
        let button = toggle.exists ? toggle : app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
        reveal(app, button)
        XCTAssertTrue(button.exists, label)
        button.tap()
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let done = app.buttons[s.done].firstMatch
        if done.exists && done.isHittable { done.tap() } else { app.typeText("\n") }
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }

    private func reveal(_ app: XCUIApplication, _ target: XCUIElement) {
        // A keyboard leaving the screen re-lays out the whole scroll view, and reading a frame in
        // that moment raised a stale-snapshot failure on iOS 26.5 where iOS 27 had already
        // settled. Let it go first; a keyboard that stays is reported by the failure that follows.
        if app.keyboards.firstMatch.exists {
            dismissKeyboard(app)
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
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

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if name.contains("-form") { print("LIMEN_UI_TREE \(app.debugDescription)") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
        try? app.screenshot().pngRepresentation.write(to: file)
        print("LIMEN_UI_SCREENSHOT \(file.path)")
    }
}

/// Audit failures remain failures and their screenshots stay in the result bundle.
@MainActor
final class AccessibilityJourneyTest: XCTestCase {
    func testEnglishDefault() throws { try audit(.en, category: "UICTContentSizeCategoryL") }
    func testFrenchLarge() throws { try audit(.fr, category: "UICTContentSizeCategoryXXXL") }
    func testGermanLargestAccessibility() throws { try audit(.de, category: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testItalianLargestAccessibility() throws { try audit(.it, category: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testRomanshLargestAccessibility() throws { try audit(.rm, category: "UICTContentSizeCategoryAccessibilityXXXL") }

    func testFrenchLargeVisibleAddress() throws { try auditVisibleFormControl(.fr, category: "UICTContentSizeCategoryXXXL", address: true) }
    func testGermanLargestVisibleExit() throws { try auditVisibleFormControl(.de, category: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testItalianLargestVisibleExit() throws { try auditVisibleFormControl(.it, category: "UICTContentSizeCategoryAccessibilityXXXL") }
    func testRomanshLargestVisibleExit() throws { try auditVisibleFormControl(.rm, category: "UICTContentSizeCategoryAccessibilityXXXL") }

    func testMainHandoverScreens() throws {
        let app = XCUIApplication()
        let s = Str(.en)
        app.launchArguments = ["LIMEN_DEMO", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["LIMEN_LANG"] = "En"
        app.launch()
        let dossier = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", s.stepDossier)).firstMatch
        XCTAssertTrue(dossier.waitForExistence(timeout: 30))
        record(app, "En-hub-audit")
        try performLoggedAudit(app, "En-hub-audit")
        dossier.tap()
        record(app, "En-dossier-audit")
        try performLoggedAudit(app, "En-dossier-audit")
        app.buttons[s.back].firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", s.stepInspection)).firstMatch.tap()
        record(app, "En-inspection-audit")
        try performLoggedAudit(app, "En-inspection-audit")
        app.buttons[s.back].firstMatch.tap()
        app.buttons[s.hubClose].tap()
        record(app, "En-review-audit")
        try performLoggedAudit(app, "En-review-audit")
    }

    private func audit(_ lang: Lang, category: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["LIMEN_RESET", "-UIPreferredContentSizeCategoryName", category]
        app.launchEnvironment["LIMEN_LANG"] = lang.rawValue
        app.launch()
        let s = Str(lang)
        XCTAssertTrue(app.buttons[s.startNewSession].waitForExistence(timeout: 30))
        record(app, "\(lang.rawValue)-\(category)-landing")
        try performLoggedAudit(app, "\(lang.rawValue)-\(category)-landing")
        app.buttons[s.startNewSession].tap()
        record(app, "\(lang.rawValue)-\(category)-form")
        try performLoggedAudit(app, "\(lang.rawValue)-\(category)-form")
    }

    // Initial large-type audits retain their unfiltered results. The control at the scroll edge
    // has no complete rendered label/background there, so inspect it again fully inside the
    // viewport. This is another unfiltered audit, never an exclusion for contrast findings.
    private func auditVisibleFormControl(_ lang: Lang, category: String, address: Bool = false) throws {
        let app = XCUIApplication()
        let s = Str(lang)
        app.launchArguments = ["LIMEN_RESET", "-UIPreferredContentSizeCategoryName", category]
        app.launchEnvironment["LIMEN_LANG"] = lang.rawValue
        app.launch()
        XCTAssertTrue(app.buttons[s.startNewSession].waitForExistence(timeout: 30))
        app.buttons[s.startNewSession].tap()
        let target = app.buttons[address ? s.identityAddress : s.exit]
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let viewport = scroll.frame
        // Reveal the whole target with a small margin. Centering it unnecessarily drags the
        // next section's heading into the clipping edge, where a pixel contrast scan is invalid.
        let distance = max(0, target.frame.maxY - (viewport.maxY - 12))
        let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let to = from.withOffset(CGVector(dx: 0, dy: -distance))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertGreaterThanOrEqual(target.frame.minY, viewport.minY)
        XCTAssertLessThanOrEqual(target.frame.maxY, viewport.maxY)
        record(app, "\(lang.rawValue)-\(category)-visible-control-form")
        try performLoggedAudit(app, "\(lang.rawValue)-\(category)-visible-control-form")
    }

    // The result bundle keeps only an issue's one-word title, so a failed run could not say which
    // element or which ratio. Log the measured detail for every issue and still report it: a
    // handler returning false suppresses nothing, so the audit's verdict is unchanged.
    private func performLoggedAudit(_ app: XCUIApplication, _ screen: String) throws {
        try app.performAccessibilityAudit { issue in
            let element = issue.element.map { String($0.debugDescription.prefix(160)) } ?? "no element"
            print("LIMEN_AUDIT_ISSUE screen=\(screen) type=\(issue.auditType.rawValue) \(issue.compactDescription) :: \(issue.detailedDescription) :: \(element)")
            return false
        }
    }

    private func record(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if name.contains("-form") { print("LIMEN_UI_TREE \(app.debugDescription)") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
        try? app.screenshot().pngRepresentation.write(to: file)
        print("LIMEN_UI_SCREENSHOT \(file.path)")
    }
}
