import Foundation
import Testing
@testable import LimenKit

/// The exported document's name, case for case as Android's `DocumentNameTest` states it: the
/// address and the handover's day, dashes between, numbered on a same-day repeat.
@Suite struct DocumentNameTests {
    /// 21 October 2026 at noon in the device zone, the day of the export when the handover has none.
    private var exportDay: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12)) ?? Date()
    }

    @Test func theNameIsTheAddressAndTheHandoverDayWithDashesBetween() {
        #expect(Exports.documentName(address: "Avenue de la Mesure 30", handoverDate: "2026-10-13", now: exportDay) == "Avenue-de-la-Mesure-30-2026-10-13")
    }

    @Test func lettersFoldToAsciiAndAnythingElseIsOneDash() {
        #expect(Exports.documentName(address: "Rue de l’Église 5", handoverDate: "2026-10-13", now: exportDay) == "Rue-de-l-Eglise-5-2026-10-13")
        #expect(Exports.documentName(address: "Mühlestrasse 7", handoverDate: "2026-10-13", now: exportDay) == "Muhlestrasse-7-2026-10-13")
        #expect(Exports.documentName(address: "  Via  Sasso, 12 ", handoverDate: "2026-10-13", now: exportDay) == "Via-Sasso-12-2026-10-13")
    }

    @Test func aBlankAddressIsNamedLimenAndAnUnsetDayIsTheDayOfTheExport() {
        #expect(Exports.documentName(address: "", handoverDate: "", now: exportDay) == "Limen-2026-10-21")
        #expect(Exports.documentName(address: "Auditstrasse 1", handoverDate: "13/10/2026", now: exportDay) == "Auditstrasse-1-2026-10-21")
    }

    @Test func theAddressIsCutAtEightyCharacters() {
        #expect(Exports.documentName(address: String(repeating: "a", count: 100), handoverDate: "2026-10-13", now: exportDay) == String(repeating: "a", count: 80) + "-2026-10-13")
    }

    @Test func aSecondExportOfTheDayTakesTheNextFreeNumber() throws {
        let folder = try temporaryRoot()
        try writeText("pdf", to: folder.appendingPathComponent("X-2026-10-13.pdf"))
        // The twin's name counts too: a PDF and an HTML copy share one stem.
        try writeText("html", to: folder.appendingPathComponent("X-2026-10-13-2.html"))
        #expect(Exports.unusedName("X-2026-10-13", in: [folder]) == "X-2026-10-13-3")
        #expect(Exports.unusedName("Y-2026-10-13", in: [folder]) == "Y-2026-10-13")
    }
}
