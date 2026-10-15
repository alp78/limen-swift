import LimenKit
import XCTest

/// The screens the 15 October 2026 simplification names, in French, from an empty store: the
/// new-session form top and bottom, Brouillon returning to the list with the draft present,
/// Valider opening the hub, the hub with its three doors and the missing-data panel, the room
/// picker, a room's action row, the signature step, and the records list with FINALISER and
/// SORTIE. One journey, so the same screenshots come off the simulator and the iPhone.
@MainActor
final class SimplificationShotsTest: XCTestCase {
    private let s = Str(.fr)

    override func setUp() { continueAfterFailure = false }

    func testFrenchScreensOfTheSimplifiedForms() {
        let app = XCUIApplication()
        app.launchArguments = ["LIMEN_RESET", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment["LIMEN_LANG"] = "Fr"
        app.launch()
        XCTAssertTrue(app.buttons[s.startNewSession].waitForExistence(timeout: 30))

        // A draft saved from the form, found in the list under "Sans adresse".
        app.buttons[s.startNewSession].tap()
        XCTAssertTrue(app.buttons[s.role(.tenant)].waitForExistence(timeout: 15))
        let draft = app.buttons["save-draft"]
        let validate = app.buttons["start-session"]
        XCTAssertTrue(draft.exists && validate.exists, "the form carries its two keys")
        XCTAssertFalse(draft.isEnabled, "Brouillon waits for the name")
        XCTAssertFalse(validate.isEnabled, "Valider waits for the name")
        fill(app, s.firstName, "Claire")
        fill(app, s.lastName, "Exemple")
        reveal(app, app.buttons[s.role(.tenant)])
        shoot(app, "fr-01-form-top")
        reveal(app, validate)
        XCTAssertTrue(draft.isEnabled && validate.isEnabled)
        shoot(app, "fr-02-form-bottom")
        draft.tap()
        XCTAssertTrue(element(app, s.allSessions).waitForExistence(timeout: 15), "Brouillon returns to the records list")
        XCTAssertTrue(element(app, s.noAddress).waitForExistence(timeout: 15), "the draft is in the list")
        XCTAssertTrue(app.buttons[s.finalizeEntryFirst].firstMatch.exists, "a draft entry offers FINALISER")
        shoot(app, "fr-03-draft-in-list")
        app.buttons[s.back].firstMatch.tap()

        // A record validated from the form opens on its hub.
        XCTAssertTrue(app.buttons[s.startNewSession].waitForExistence(timeout: 15))
        app.buttons[s.startNewSession].tap()
        XCTAssertTrue(app.buttons[s.role(.tenant)].waitForExistence(timeout: 15))
        fill(app, s.firstName, "Claire")
        fill(app, s.lastName, "Exemple")
        reveal(app, validate)
        validate.tap()
        let record = key(app, s.hubRecordLead)
        XCTAssertTrue(record.waitForExistence(timeout: 30), "Valider opens the hub")
        XCTAssertTrue(key(app, s.hubInspectionLead).exists && key(app, s.hubDossierLead).exists, "three doors")
        XCTAssertTrue(element(app, s.stillMissing).exists, "the missing data panel")
        shoot(app, "fr-04-hub-three-doors")

        // The room picker and a room's action row.
        tap(app, s.stepInspection)
        XCTAssertTrue(app.buttons[s.room(.kitchen)].waitForExistence(timeout: 15))
        shoot(app, "fr-05-room-picker")
        app.buttons[s.room(.kitchen)].tap()
        app.buttons[s.useSelectedRooms].tap()
        tap(app, s.room(.kitchen))
        tap(app, s.roomActions)
        let next = key(app, s.nextRoom)
        reveal(app, next)
        XCTAssertTrue(app.buttons[s.moveUp].exists && app.buttons[s.removeRoom].exists, "the actions opened")
        shoot(app, "fr-06-room-action-row")
        tap(app, s.roomInspected)
        app.buttons[s.back].firstMatch.tap()
        app.buttons[s.back].firstMatch.tap()

        // The dossier, enough of it to finalize.
        tap(app, s.stepDossier)
        fill(app, s.address, "Rue de l’Audit 12")
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
            fill(app, "legal-note-\(requirement.rawValue)", "Pièces vérifiées, jeu d’essai synthétique")
            dismissKeyboard(app)
        }
        fill(app, s.role(.landlord), "Bailleur Exemple")
        dismissKeyboard(app)
        let noKeys = app.buttons[s.keyTransfer(.noPhysicalKeys)]
        reveal(app, noKeys)
        noKeys.tap()
        app.buttons[s.back].firstMatch.tap()

        // The record door, the review, the signature step, the finalization.
        tap(app, s.hubRecordLead)
        let preview = app.buttons["preview-document"]
        reveal(app, preview)
        preview.tap()
        XCTAssertTrue(app.buttons["confirm-review"].waitForExistence(timeout: 30))
        app.buttons["confirm-review"].tap()
        tap(app, s.stepSign)
        XCTAssertTrue(element(app, s.oneSided).waitForExistence(timeout: 15))
        shoot(app, "fr-07-signature-step")
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
        XCTAssertTrue(finalize.isEnabled)
        finalize.tap()
        XCTAssertTrue(app.buttons[s.exportPdf].waitForExistence(timeout: 30))
        let done = app.buttons[s.done].firstMatch
        reveal(app, done)
        done.tap()

        // The list: SORTIE on the finalized entry, FINALISER on the draft, and FINALISER opens
        // the draft at its signature step.
        if !app.buttons[s.allSessions].exists { app.buttons[s.back].firstMatch.tap() }
        XCTAssertTrue(app.buttons[s.allSessions].waitForExistence(timeout: 15))
        app.buttons[s.allSessions].tap()
        let exit = app.buttons[s.exitFromThis].firstMatch
        let finish = app.buttons[s.finalizeEntryFirst].firstMatch
        XCTAssertTrue(exit.waitForExistence(timeout: 30) && finish.exists, "SORTIE and FINALISER side by side")
        shoot(app, "fr-08-records-list")
        reveal(app, finish)
        finish.tap()
        XCTAssertTrue(element(app, s.oneSided).waitForExistence(timeout: 15), "FINALISER opens the draft at the signature step")
        shoot(app, "fr-09-finaliser-opens-signatures")
    }

    // MARK: - Driving, as the parity journeys drive

    private func fill(_ app: XCUIApplication, _ label: String, _ text: String) {
        let field = app.textFields[label].firstMatch
        reveal(app, field)
        XCTAssertTrue(field.exists, label)
        field.tap()
        // The second form opens with the name the reusable identity kept from the first, and
        // typing over a prefilled field doubled it: clear what is there before writing.
        let current = (field.value as? String) ?? ""
        if !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
        let done = app.buttons[s.done].firstMatch
        if done.exists && done.isHittable { done.tap() } else { field.typeText("\n") }
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }

    private func tap(_ app: XCUIApplication, _ label: String) {
        let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
        let button = toggle.exists ? toggle : app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
        reveal(app, button)
        XCTAssertTrue(button.exists, label)
        button.tap()
    }

    private func key(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func element(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let done = app.buttons[s.done].firstMatch
        if done.exists && done.isHittable { done.tap() } else { app.typeText("\n") }
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }

    private func reveal(_ app: XCUIApplication, _ target: XCUIElement) {
        if app.keyboards.firstMatch.exists {
            dismissKeyboard(app)
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
        }
        // The form's two keys sit under the scroll view, so their viewport is the window.
        let pinned = ["start-session", "save-draft"].contains(target.identifier)
        for _ in 0..<30 {
            let scroller = app.scrollViews.firstMatch
            let viewport = scroller.exists && !pinned ? scroller.frame : app.frame
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

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
        try? screenshot.pngRepresentation.write(to: file)
        print("LIMEN_UI_SCREENSHOT \(file.path)")
    }
}
