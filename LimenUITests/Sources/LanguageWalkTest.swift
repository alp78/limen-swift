import LimenKit
import XCTest

/// The same walk through the whole instrument once per language, driven by the words that language
/// actually speaks. The expectations come from `Str` rather than from a table typed out here, so a
/// translation that changes takes the test with it and a translation that never reaches the screen
/// fails it: the five languages are checked by using them, not by reading them.
///
/// One method per language rather than one loop, because a failure has to name the language in the
/// report, and because XCTest gives each method its own app process, which is how the walk gets to
/// start twice: once on an empty store for the landing and the forms, once on the seeded draft for
/// the steps.
final class LanguageWalkTest: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testTheWalkInEnglish() { walk(.en) }
    func testTheWalkInFrench() { walk(.fr) }
    func testTheWalkInGerman() { walk(.de) }
    func testTheWalkInItalian() { walk(.it) }
    func testTheWalkInRomansh() { walk(.rm) }

    // MARK: - The walk

    private func walk(_ lang: Lang) {
        let s = Str(lang)
        let tag = lang.rawValue.lowercased()

        var app = launch(lang, ["LIMEN_RESET"])
        landing(app, s, tag, lang)
        newSessionForm(app, s, tag, lang)
        privacyAndLicences(app, s, tag, lang)
        app.terminate()

        app = launch(lang, ["LIMEN_DEMO"])
        hubAndInspection(app, s, tag, lang)
        dossierAndCanton(app, s, tag, lang)
        reviewAndSignature(app, s, tag, lang)
    }

    private func landing(_ app: XCUIApplication, _ s: Str, _ tag: String, _ lang: Lang) {
        XCTAssertTrue(app.buttons[s.startNewSession].waitForExistence(timeout: 60), "no start key in \(lang.rawValue)")
        XCTAssertTrue(app.buttons[s.allSessions].exists, "no sessions key in \(lang.rawValue)")
        XCTAssertTrue(app.buttons[s.dataAndPrivacy].exists, "no privacy key in \(lang.rawValue)")
        shoot(app, "\(tag)-01-landing")
    }

    private func newSessionForm(_ app: XCUIApplication, _ s: Str, _ tag: String, _ lang: Lang) {
        app.buttons[s.startNewSession].tap()
        XCTAssertTrue(app.buttons[s.role(.tenant)].waitForExistence(timeout: 15), "no tenant choice in \(lang.rawValue)")
        XCTAssertTrue(app.buttons[s.actorLandlordPrivate].exists, "no landlord choice in \(lang.rawValue)")

        // The agency is the one actor with a field of its own, so choosing it proves the form
        // reacts in this language and not only that its keys are translated.
        app.buttons[s.actorAgency].tap()
        XCTAssertTrue(element(app, s.companyName).waitForExistence(timeout: 10), "no agency field in \(lang.rawValue)")
        XCTAssertTrue(app.buttons[s.exit].exists, "no exit kind in \(lang.rawValue)")
        app.buttons[s.exit].tap()
        app.buttons[s.entry].tap()
        XCTAssertTrue(element(app, s.phoneNumber).exists, "no phone field in \(lang.rawValue)")
        shoot(app, "\(tag)-02-new-session")
        app.buttons[s.back].firstMatch.tap()
    }

    private func privacyAndLicences(_ app: XCUIApplication, _ s: Str, _ tag: String, _ lang: Lang) {
        XCTAssertTrue(app.buttons[s.dataAndPrivacy].waitForExistence(timeout: 15), "no way back to the landing in \(lang.rawValue)")
        app.buttons[s.dataAndPrivacy].tap()
        XCTAssertTrue(element(app, s.privacyTitle).waitForExistence(timeout: 15), "no privacy title in \(lang.rawValue)")
        XCTAssertTrue(element(app, s.controllerTitle).exists, "no controller panel in \(lang.rawValue)")
        shoot(app, "\(tag)-03-privacy")

        app.swipeUp()
        XCTAssertTrue(app.buttons[s.openLicences].waitForExistence(timeout: 10), "no licences key in \(lang.rawValue)")
        app.buttons[s.openLicences].tap()
        // The notice is one document in one language, as Apache-2.0 section 4(d) asks for it, so
        // the assertion here is its own words and the same in every run.
        XCTAssertTrue(element(app, "Cantonal flags of Switzerland").waitForExistence(timeout: 15), "the notice did not reach the bundle")
        shoot(app, "\(tag)-04-licences")
        app.buttons[s.back].firstMatch.tap()
        XCTAssertTrue(element(app, s.privacyTitle).waitForExistence(timeout: 15), "no way out of the licences in \(lang.rawValue)")
    }

    private func hubAndInspection(_ app: XCUIApplication, _ s: Str, _ tag: String, _ lang: Lang) {
        XCTAssertTrue(element(app, s.stepInspection).waitForExistence(timeout: 60), "no inspection door in \(lang.rawValue)")
        shoot(app, "\(tag)-05-hub")

        element(app, s.stepInspection).tap()
        XCTAssertTrue(element(app, s.room(.room)).waitForExistence(timeout: 15), "no rooms in \(lang.rawValue)")
        shoot(app, "\(tag)-06-inspection")

        key(app, s.stepObjects).tap()
        XCTAssertTrue(element(app, s.addObject).waitForExistence(timeout: 15), "no objects step in \(lang.rawValue)")
        shoot(app, "\(tag)-07-objects")
        app.buttons[s.back].firstMatch.tap()
        XCTAssertTrue(element(app, s.room(.room)).waitForExistence(timeout: 15), "back did not retrace to the rooms in \(lang.rawValue)")
        app.buttons[s.back].firstMatch.tap()
    }

    private func dossierAndCanton(_ app: XCUIApplication, _ s: Str, _ tag: String, _ lang: Lang) {
        XCTAssertTrue(element(app, s.stepDossier).waitForExistence(timeout: 15), "no dossier door in \(lang.rawValue)")
        element(app, s.stepDossier).tap()
        XCTAssertTrue(element(app, s.parties).waitForExistence(timeout: 15), "no parties panel in \(lang.rawValue)")
        shoot(app, "\(tag)-08-dossier")

        let cantonKey = app.buttons[s.selectCanton]
        XCTAssertTrue(cantonKey.waitForExistence(timeout: 10), "no canton key in \(lang.rawValue)")
        cantonKey.tap()
        let zurich = app.buttons[s.canton(.zh)]
        XCTAssertTrue(zurich.waitForExistence(timeout: 15), "no canton grid in \(lang.rawValue)")
        shoot(app, "\(tag)-09-cantons")
        zurich.tap()
        // Choosing a canton is what makes the legal overlay speak, and its rows are the longest
        // sentences in the app: if a language breaks a panel, it breaks here.
        XCTAssertTrue(element(app, s.initialRentFormRule(.required)).waitForExistence(timeout: 15), "no legal overlay in \(lang.rawValue)")
        shoot(app, "\(tag)-10-legal-overlay")
        app.buttons[s.back].firstMatch.tap()
    }

    private func reviewAndSignature(_ app: XCUIApplication, _ s: Str, _ tag: String, _ lang: Lang) {
        XCTAssertTrue(app.buttons[s.hubClose].waitForExistence(timeout: 15), "no close key in \(lang.rawValue)")
        app.buttons[s.hubClose].tap()
        XCTAssertTrue(element(app, s.objectLabel).waitForExistence(timeout: 15), "no review in \(lang.rawValue)")
        shoot(app, "\(tag)-11-review")

        app.swipeUp()
        let signatures = key(app, s.stepSign)
        XCTAssertTrue(signatures.waitForExistence(timeout: 10), "no signatures key in \(lang.rawValue)")
        signatures.tap()
        XCTAssertTrue(element(app, s.oneSided).waitForExistence(timeout: 15), "no signature page in \(lang.rawValue)")
        shoot(app, "\(tag)-12-sign")

        app.buttons[s.signKey].firstMatch.tap()
        let pad = element(app, s.signaturePad)
        XCTAssertTrue(pad.waitForExistence(timeout: 15), "no ink pad in \(lang.rawValue)")
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: pad.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4)))
        shoot(app, "\(tag)-13-ink")
        app.buttons[s.saveInk].tap()
        XCTAssertTrue(element(app, s.signed).waitForExistence(timeout: 15), "the ink was not kept in \(lang.rawValue)")
        shoot(app, "\(tag)-14-signed")
    }

    // MARK: - Driving

    private func launch(_ lang: Lang, _ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launchEnvironment["LIMEN_LANG"] = lang.rawValue
        app.launch()
        return app
    }

    /// Text inside a SwiftUI button is folded into the button's own label, so a row is found by the
    /// words its label contains rather than as a static text of its own.
    private func element(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// A key whose view uppercases what `Str` holds in sentence case, matched on the word rather
    /// than on the casing so the one lookup serves both shapes.
    private func key(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
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
}
