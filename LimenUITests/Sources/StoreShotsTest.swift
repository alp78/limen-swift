import LimenKit
import XCTest

/// The eight store screenshots, once per language, in the order the Play listing uses.
///
/// The September set was captured by hand and could not be redone after a change to a screen, so
/// this walks the same record on the simulator and attaches the PNGs the listing takes. The scene
/// behind it is Android's `StoreScene.kt`, mirrored in `StoreScene.swift`: three defects in three
/// rooms, each with one photograph, so an agency comparing the two stores sees one handover.
///
/// In upload order: 01 home, 02 rooms, 03 the kitchen's defect with its photograph, 04 the canton
/// overlay, 05 the review, 06 the agency's representative signing, 07 the finalized record's cover
/// in the preview, 08 the annex's first photograph page. `make shots` takes them out of the result
/// bundle; the simulator's status bar is set by `xcrun simctl status_bar` before the run.
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
        let scene = StoreScene.of(lang)
        let tag = lang.rawValue.lowercased()
        let app = XCUIApplication()
        app.launchArguments = ["LIMEN_STORE"]
        app.launchEnvironment["LIMEN_LANG"] = lang.rawValue
        // Shot 08 is the annex page that carries the living room photograph's file name. The
        // third preview of the walk opens on it: the first is the draft the review validates, the
        // second the finalized cover of shot 07.
        app.launchEnvironment["LIMEN_PREVIEW_FIND"] = StoreScene.shot("d3")?.file ?? ""
        app.launchEnvironment["LIMEN_PREVIEW_FIND_FROM"] = "3"
        app.launch()

        // 01 the app's face, and the two ways into a record
        XCTAssertTrue(app.buttons[s.startNewSession].waitForExistence(timeout: 60), "no landing in \(lang.rawValue)")
        shoot(app, "\(tag)-01-home")

        app.buttons[s.allSessions].tap()
        // By the scene's street, not by the word "Exit": the list's filter row carries that word
        // too, sits above the cards, and was what the first match found.
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", scene.street)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "the seeded record is not in the list for \(lang.rawValue)")
        card.tap()

        // 02 the rooms, three of them carrying one defect
        XCTAssertTrue(element(app, s.stepInspection).waitForExistence(timeout: 20), "no hub in \(lang.rawValue)")
        element(app, s.stepInspection).tap()
        XCTAssertTrue(element(app, s.room(.kitchen)).waitForExistence(timeout: 15), "no rooms in \(lang.rawValue)")
        shoot(app, "\(tag)-02-rooms")

        // 03 the kitchen's defect, its photograph and the tenant's stated position; the thumbnail
        // decodes off the main thread, so the frame waits a moment for it.
        element(app, s.room(.kitchen)).tap()
        let defect = element(app, scene.kitchenStain)
        XCTAssertTrue(defect.waitForExistence(timeout: 15), "no defect on the room in \(lang.rawValue)")
        defect.tap()
        XCTAssertTrue(element(app, s.tenantResponseLabel).waitForExistence(timeout: 15), "no defect editor in \(lang.rawValue)")
        settle(2)
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
        settleUnderRail(app, overlayTitle)
        shoot(app, "\(tag)-04-canton-overlay")
        app.buttons[s.back].firstMatch.tap()

        // 05 the whole record, before anyone signs it
        let record = key(app, s.hubRecordLead)
        XCTAssertTrue(record.waitForExistence(timeout: 15), "no record door in \(lang.rawValue)")
        record.tap()
        XCTAssertTrue(element(app, s.objectLabel).waitForExistence(timeout: 15), "no review in \(lang.rawValue)")
        shoot(app, "\(tag)-05-review")

        // 06 the agency's representative signs first, so the pad's title carries the agency's
        // signer; the tenant follows, because a finalized record needs both outcomes.
        let preview = app.buttons["preview-document"]
        reveal(app, preview)
        preview.tap()
        XCTAssertTrue(app.buttons["confirm-review"].waitForExistence(timeout: 30))
        app.buttons["confirm-review"].tap()
        let signatures = key(app, s.stepSign)
        XCTAssertTrue(signatures.waitForExistence(timeout: 10), "no signatures key in \(lang.rawValue)")
        reveal(app, signatures)
        signatures.tap()
        let landlordKey = app.buttons["sign-landlord"]
        XCTAssertTrue(landlordKey.waitForExistence(timeout: 15), "no sign key for the agency in \(lang.rawValue)")
        reveal(app, landlordKey)
        landlordKey.tap()
        let pad = element(app, s.signaturePad)
        XCTAssertTrue(pad.waitForExistence(timeout: 15), "no ink pad in \(lang.rawValue)")
        sign(pad)
        shoot(app, "\(tag)-06-signature")
        app.buttons[s.saveInk].tap()
        let tenantKey = app.buttons["sign-tenant"]
        XCTAssertTrue(tenantKey.waitForExistence(timeout: 15), "no sign key for the tenant in \(lang.rawValue)")
        reveal(app, tenantKey)
        tenantKey.tap()
        let second = element(app, s.signaturePad)
        XCTAssertTrue(second.waitForExistence(timeout: 15), "no second ink pad in \(lang.rawValue)")
        sign(second)
        app.buttons[s.saveInk].tap()

        // The app finalizes: the enabled key proves the scene satisfies every completion rule.
        let finalize = key(app, s.finalizeRecord)
        XCTAssertTrue(finalize.waitForExistence(timeout: 15), "no finalize key in \(lang.rawValue)")
        app.swipeUp()
        press(finalize)
        let finalized = element(app, s.finalized).waitForExistence(timeout: 30)
        // The tree names what held the record back, which the one-word failure cannot.
        if !finalized { print("LIMEN_UI_TREE \(app.debugDescription)") }
        XCTAssertTrue(finalized, "the record did not finalize in \(lang.rawValue)")

        // 07 the record's cover, as the preview shows the finalized document. Finalizing arrives
        // on the export step; the preview panel is on the sign step, one press back.
        app.buttons[s.back].firstMatch.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 15), "no preview key on the finalized record in \(lang.rawValue)")
        openPreview(app, s)
        // A tablet's sheet fits the page to its width and is shorter than the cover, whose last
        // panel carries the reference under the finalized pill. The page's white margin above the
        // banner is about what the reference lacks, so a drag that size shows both; a phone's frame
        // already holds them.
        if UIDevice.current.userInterfaceIdiom == .pad { drag(app, up: 80) }
        shoot(app, "\(tag)-07-record-cover")
        app.buttons[s.done].tap()

        // 08 the annex's first photograph page, on the third preview of the walk.
        reveal(app, preview)
        openPreview(app, s)
        shoot(app, "\(tag)-08-photo-annex")
        app.buttons[s.done].tap()
    }

    // MARK: - Driving

    /// Opens the preview sheet and waits for the document: the pill row appears once the PDF is
    /// written, and the view needs a moment more to lay the page out and scroll to it.
    private func openPreview(_ app: XCUIApplication, _ s: Str) {
        app.buttons["preview-document"].tap()
        XCTAssertTrue(app.buttons[s.accessibleCopy].waitForExistence(timeout: 90), "the preview did not render")
        settle(3)
    }

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
    /// the column, and a step that has just changed is still settling. This scrolls the list until
    /// the hit test agrees. Nothing is asked of the element before it exists, and the list is the
    /// tallest scroll view on screen, not the rail above it.
    private func reveal(_ app: XCUIApplication, _ target: XCUIElement) {
        for _ in 0..<30 {
            let scroller = app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height } ?? app.scrollViews.firstMatch
            var viewport = scroller.exists ? scroller.frame : app.frame
            var upwards = true
            if target.exists {
                if target.identifier == "start-session" { viewport = app.frame }
                let top = viewport.minY + (target.elementType == .textField ? min(55, viewport.height * 0.2) : 8)
                let bottom = viewport.maxY - 24
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

    /// Android's walk scrolls the overlay's title to just under the dossier's sticky rail before
    /// its shot (`settleUnderStickyHeader`), so the frame is the panel and not the object fields
    /// above it; the creep alone stopped the moment the title entered at the bottom of a phone.
    /// The rail's chips read ticked or open (✓, ○), and the lowest of them above the title is the
    /// rail's edge. The distance is measured again after each drag, because a drag's first points
    /// go to the scroll view's slop.
    private func settleUnderRail(_ app: XCUIApplication, _ title: XCUIElement) {
        let chips = NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "✓ ", "○ ")
        for _ in 0..<4 {
            let titleTop = title.frame.minY
            let railBottom = app.descendants(matching: .any).matching(chips).allElementsBoundByIndex
                .map(\.frame).filter { $0.minY < titleTop }.map(\.maxY).max() ?? app.frame.minY
            let delta = min(titleTop - railBottom - 12, app.frame.height * 0.55)
            if delta < 8 { return }
            drag(app, up: delta)
        }
    }

    /// A slow drag held at its end, so the list or the document moves by the distance asked and
    /// does not coast past it. It starts low on the screen, inside the list and inside a sheet.
    private func drag(_ app: XCUIApplication, up points: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -points)), withVelocity: .slow, thenHoldForDuration: 0.4)
        settle(1)
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

    /// Waits for a frame to finish drawing what the hierarchy already reports: a decoded thumbnail,
    /// a rendered page. An expectation that never fulfils is the one wait XCTest does not shortcut.
    private func settle(_ seconds: TimeInterval) {
        _ = XCTWaiter().wait(for: [expectation(description: "settle")], timeout: seconds)
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
