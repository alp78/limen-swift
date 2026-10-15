import LimenKit
import XCTest

/// The eight store screenshots, once per language, in the order the Play listing already uses.
///
/// The Android set was captured by hand on an emulator. Doing the same here would be eighty manual
/// captures across two device classes and would have to be redone by hand after any change to a
/// screen, so this walks the same eight states automatically instead. The scene behind it is the
/// one the Play listing ships, transcribed from those screenshots into `StoreScene`, so an
/// agency comparing the two stores sees the same handover in both.
///
/// The shots, in upload order:
///   01 home, 02 rooms, 03 defect editor, 04 canton overlay,
///   05 review, 06 signature, 07 finalized, 08 exported
@MainActor
final class StoreShotsTest: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testStoreShotsInEnglish() { walk(.en) }
    func testStoreShotsInFrench() { walk(.fr) }
    func testStoreShotsInGerman() { walk(.de) }
    func testStoreShotsInItalian() { walk(.it) }
    func testStoreShotsInRomansh() { walk(.rm) }

    private func walk(_ lang: Lang) {
        let s = Str(lang)
        let tag = lang.rawValue.lowercased()
        let app = XCUIApplication()
        app.launchArguments = ["LIMEN_STORE"]
        app.launchEnvironment["LIMEN_LANG"] = lang.rawValue
        app.launch()

        // 01 the app's face, and the two ways into a record
        XCTAssertTrue(app.buttons[s.startNewSession].waitForExistence(timeout: 60), "no landing in \(lang.rawValue)")
        shoot(app, "\(tag)-01-home")

        app.buttons[s.allSessions].tap()
        let card = element(app, s.exit)
        XCTAssertTrue(card.waitForExistence(timeout: 15), "the seeded record is not in the list for \(lang.rawValue)")
        card.tap()

        // 02 the rooms, each carrying its own inspected mark
        XCTAssertTrue(element(app, s.stepInspection).waitForExistence(timeout: 20), "no hub in \(lang.rawValue)")
        element(app, s.stepInspection).tap()
        XCTAssertTrue(element(app, s.room(.kitchen)).waitForExistence(timeout: 15), "no rooms in \(lang.rawValue)")
        shoot(app, "\(tag)-02-rooms")

        // 03 one defect, its controls for photographs, and the tenant's stated position
        element(app, s.room(.kitchen)).tap()
        let defect = element(app, StoreScene.of(lang).defect)
        XCTAssertTrue(defect.waitForExistence(timeout: 15), "no defect on the room in \(lang.rawValue)")
        defect.tap()
        XCTAssertTrue(element(app, s.tenantResponseLabel).waitForExistence(timeout: 15), "no defect editor in \(lang.rawValue)")
        shoot(app, "\(tag)-03-defect-editor")

        // Back retraces the route rather than jumping out: the defect, then the room, then the
        // rooms, and the hub is one further. Counted rather than assumed, so a step added to the
        // route later does not silently break the walk here.
        var hops = 0
        while !element(app, s.stepDossier).waitForExistence(timeout: 2), hops < 4 {
            app.buttons[s.back].firstMatch.tap()
            hops += 1
        }

        // 04 the canton overlay, its legal basis and its dated period
        XCTAssertTrue(element(app, s.stepDossier).waitForExistence(timeout: 15), "no way back to the hub in \(lang.rawValue)")
        element(app, s.stepDossier).tap()
        XCTAssertTrue(element(app, s.parties).waitForExistence(timeout: 15), "no dossier in \(lang.rawValue)")
        // Crept down rather than swiped: a full swipe carries the overlay's header off the top and
        // leaves the shot showing the end of the panel, where the legal basis and its dated period
        // are exactly what this frame exists to show. A tablet usually needs no scroll at all.
        let overlayTitle = element(app, s.legalOverlayTitle)
        var creeps = 0
        while !(overlayTitle.exists && overlayTitle.isHittable), creeps < 6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)))
            creeps += 1
        }
        XCTAssertTrue(overlayTitle.waitForExistence(timeout: 10), "no canton overlay in \(lang.rawValue)")
        shoot(app, "\(tag)-04-canton-overlay")
        app.buttons[s.back].firstMatch.tap()

        // 05 the whole protocol, before anyone signs it
        XCTAssertTrue(app.buttons[s.hubClose].waitForExistence(timeout: 15), "no close key in \(lang.rawValue)")
        app.buttons[s.hubClose].tap()
        XCTAssertTrue(element(app, s.objectLabel).waitForExistence(timeout: 15), "no review in \(lang.rawValue)")
        shoot(app, "\(tag)-05-review")

        // 06 signing on the device
        let preview = app.buttons["preview-document"]
        reveal(app, preview)
        preview.tap()
        XCTAssertTrue(app.buttons["confirm-review"].waitForExistence(timeout: 30))
        app.buttons["confirm-review"].tap()
        let signatures = key(app, s.stepSign)
        XCTAssertTrue(signatures.waitForExistence(timeout: 10), "no signatures key in \(lang.rawValue)")
        reveal(app, signatures)
        signatures.tap()
        XCTAssertTrue(app.buttons[s.signKey].firstMatch.waitForExistence(timeout: 15), "no sign key in \(lang.rawValue)")
        reveal(app, app.buttons[s.signKey].firstMatch)
        app.buttons[s.signKey].firstMatch.tap()
        let pad = element(app, s.signaturePad)
        XCTAssertTrue(pad.waitForExistence(timeout: 15), "no ink pad in \(lang.rawValue)")
        sign(pad)
        shoot(app, "\(tag)-06-signature")
        app.buttons[s.saveInk].tap()

        // The second party signs too, because a finalized record needs both outcomes.
        XCTAssertTrue(app.buttons[s.signKey].firstMatch.waitForExistence(timeout: 15), "no second sign key in \(lang.rawValue)")
        reveal(app, app.buttons[s.signKey].firstMatch)
        app.buttons[s.signKey].firstMatch.tap()
        let second = element(app, s.signaturePad)
        XCTAssertTrue(second.waitForExistence(timeout: 15), "no second ink pad in \(lang.rawValue)")
        sign(second)
        app.buttons[s.saveInk].tap()

        // 07 the sealed record, its evidence fingerprint and the five languages of the document
        let finalize = key(app, s.finalizeRecord)
        XCTAssertTrue(finalize.waitForExistence(timeout: 15), "no finalize key in \(lang.rawValue)")
        app.swipeUp()
        press(finalize)
        XCTAssertTrue(element(app, s.finalized).waitForExistence(timeout: 30), "the record did not finalize in \(lang.rawValue)")
        shoot(app, "\(tag)-07-finalized")

        // 08 the exported document and its delivery record
        // Finalizing arrives on the export page itself, so there is no step key to press first.
        // Exact label rather than a substring: German's "PDF EXPORTIEREN" contains the step's own
        // word "EXPORT", and a contains-match found the disabled key on the page behind this one.
        let exportKey = app.buttons[s.exportPdf]
        XCTAssertTrue(exportKey.waitForExistence(timeout: 15), "no export page in \(lang.rawValue)")
        press(exportKey)
        XCTAssertTrue(app.buttons[s.open].waitForExistence(timeout: 60), "the PDF was not written in \(lang.rawValue)")
        shoot(app, "\(tag)-08-exported")
    }

    // MARK: - Driving

    /// A signature rather than a scribble: three strokes that read as handwriting at listing size.
    private func sign(_ pad: XCUIElement) {
        let marks: [(CGVector, CGVector)] = [
            (CGVector(dx: 0.14, dy: 0.62), CGVector(dx: 0.34, dy: 0.34)),
            (CGVector(dx: 0.30, dy: 0.58), CGVector(dx: 0.52, dy: 0.40)),
            (CGVector(dx: 0.48, dy: 0.44), CGVector(dx: 0.82, dy: 0.52)),
        ]
        for mark in marks {
            pad.coordinate(withNormalizedOffset: mark.0)
                .press(forDuration: 0.05, thenDragTo: pad.coordinate(withNormalizedOffset: mark.1))
        }
    }

    /// A key that exists is not always a key that can be pressed: the passing notice slides over
    /// the column, and a step that has just changed is still settling. This waits for the hit test
    /// to agree, then presses the middle of the key directly if it never does.
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

    private func press(_ element: XCUIElement) {
        let hittable = NSPredicate(format: "isHittable == true")
        let settled = expectation(for: hittable, evaluatedWith: element)
        if XCTWaiter().wait(for: [settled], timeout: 10) == .completed {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func element(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func key(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func shoot(_ app: XCUIApplication, _ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
