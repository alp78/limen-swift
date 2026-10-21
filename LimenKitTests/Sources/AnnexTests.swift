import CoreGraphics
import Foundation
import Testing
@testable import LimenKit

/// The plate sizes: up to the full width inside the card's frame, 1020 units, or 1100 units high,
/// decoded at four pixels per three units, which is 200 dpi. The Android suite asserts the same
/// table, so both apps print and decode the same sizes.
@Suite struct AnnexPlateTests {
    private struct Row {
        let width: Int, height: Int, boxWidth: Double, boxHeight: Double, pixelWidth: Int, pixelHeight: Int
    }

    private let table = [
        Row(width: 4032, height: 3024, boxWidth: 1020, boxHeight: 765, pixelWidth: 1360, pixelHeight: 1020),
        Row(width: 3024, height: 4032, boxWidth: 825, boxHeight: 1100, pixelWidth: 1100, pixelHeight: 1467),
        Row(width: 6000, height: 4000, boxWidth: 1020, boxHeight: 680, pixelWidth: 1360, pixelHeight: 907),
        Row(width: 1920, height: 1080, boxWidth: 1020, boxHeight: 573.8, pixelWidth: 1360, pixelHeight: 765),
        Row(width: 4000, height: 1000, boxWidth: 1020, boxHeight: 255, pixelWidth: 1360, pixelHeight: 340),
        Row(width: 800, height: 600, boxWidth: 1020, boxHeight: 765, pixelWidth: 800, pixelHeight: 600),
    ]

    @Test func everyRowOfTheSharedTableHoldsLongEdgeExactAndShortEdgeWithinOnePixel() {
        for row in table {
            let fit = AnnexPlate.fit(row.width, row.height)
            let label = "\(row.width) × \(row.height)"
            #expect(abs(Double(fit.boxWidth) - row.boxWidth) <= 0.05, "\(label) box width \(fit.boxWidth)")
            #expect(abs(Double(fit.boxHeight) - row.boxHeight) <= 0.05, "\(label) box height \(fit.boxHeight)")
            let landscape = row.width >= row.height
            let (long, short) = landscape ? (fit.pixelWidth, fit.pixelHeight) : (fit.pixelHeight, fit.pixelWidth)
            let (expectedLong, expectedShort) = landscape ? (row.pixelWidth, row.pixelHeight) : (row.pixelHeight, row.pixelWidth)
            #expect(long == expectedLong, "\(label) long edge")
            #expect(abs(short - expectedShort) <= 1, "\(label) short edge \(short) against \(expectedShort)")
        }
    }

    @Test func aPictureSmallerThanItsBoxIsNeverEnlarged() {
        let fit = AnnexPlate.fit(640, 480)
        #expect(fit.pixelWidth == 640)
        #expect(fit.pixelHeight == 480)
    }

    /// The decode at the plate's size: the long edge exact, the picture upright, with a quarter
    /// turn read from the header before anything is decoded.
    @Test func uprightSizeAndUprightDecodeFollowTheHeaderAndTheOrientation() throws {
        let root = try temporaryRoot()
        let sideways = root.appendingPathComponent("sideways.tiff")
        _ = try testImage(to: sideways, width: 240, height: 160, orientation: 6)
        let size = try #require(PhotoDecode.uprightSize(sideways))
        #expect(size.width == 160 && size.height == 240)
        let fit = AnnexPlate.fit(size.width, size.height)
        let plate = try #require(PhotoDecode.uprightAtSize(sideways, width: fit.pixelWidth, height: fit.pixelHeight))
        #expect(plate.width == fit.pixelWidth && plate.height == fit.pixelHeight)
        #expect(plate.width == 160 && plate.height == 240)
        // A picture larger than its plate comes down to it, to the pixel.
        let large = root.appendingPathComponent("large.png")
        _ = try testImage(to: large, width: 2400, height: 1800)
        let largeFit = AnnexPlate.fit(2400, 1800)
        let scaled = try #require(PhotoDecode.uprightAtSize(large, width: largeFit.pixelWidth, height: largeFit.pixelHeight))
        #expect(scaled.width == 1360 && scaled.height == 1020)
    }
}

/// The annex content on the record the Android suite uses, deliberately out of walkthrough order
/// in the record itself.
@Suite struct AnnexContentTests {
    private let s = Str(.fr)
    private let taken: Int64 = 1_761_030_000_000 // 21.10.2025 09:00 in Zurich

    private func evidence(_ file: String) -> PhotoEvidence {
        PhotoEvidence(file, sha256: "AB", capturedEpochMs: taken, source: .camera)
    }

    private var record: HandoverProtocol {
        var p = HandoverProtocol(id: "annex", kind: .exit, createdEpochMs: 1)
        p.rooms = [Room(id: "kitchen", kind: .kitchen), Room(id: "bath", kind: .bathroom, name: "Salle d’eau")]
        p.defects = [
            Defect(id: "d1", roomId: "bath", item: .walls, text: "Joint noirci", photos: ["d1-a.jpg"], photoEvidence: [evidence("d1-a.jpg")], chargedToTenant: true),
            Defect(id: "d2", roomId: "kitchen", item: .floor, text: "Rayure", photos: ["d2-a.jpg", "d2-b.jpg"], photoEvidence: [evidence("d2-a.jpg"), evidence("d2-b.jpg")]),
            Defect(id: "d3", text: "Panier cassé", photos: ["d3-a.jpg"], objectId: "dishwasher"),
            Defect(id: "d4", roomId: "gone", text: "Pièce supprimée", photos: ["d4-a.jpg"]),
            Defect(id: "d5", text: "Abat-jour fendu", photos: ["d5-a.jpg"], objectId: "lamp"),
        ]
        p.objects = [
            ObjectEntry(id: "dishwasher", group: .other, label: "Lave-vaisselle", roomId: "kitchen", photos: ["o1-a.jpg"]),
            ObjectEntry(id: "lamp", group: .other, label: "Lampe", photos: ["o2-a.jpg"]),
        ]
        p.details.roomPhotos["kitchen"] = [evidence("k-overview.jpg")]
        p.details.roomPhotos["bath"] = [evidence("b-overview.jpg")]
        p.details.readings = [MeterReading(id: "m1", label: "Électricité", identifier: "CH-1", value: "18342", unit: "kWh", photos: [evidence("m1-a.jpg")])]
        return p
    }

    @Test func everyPlateAppearsExactlyOnceAndNothingElse() {
        let files = AnnexContent.sections(record, s).flatMap { $0.cards.map(\.file) }
        #expect(Report.plates(record).map(\.file).sorted() == files.sorted())
        #expect(files.count == Set(files).count)
    }

    @Test func sectionsFollowTheWalkthroughOverviewThenFindingsThenObjects() {
        let sections = AnnexContent.sections(record, s)
        #expect(sections.map(\.title) == ["Cuisine", "Salle d’eau", s.objects, s.defects, s.meters])
        #expect(sections[0].cards.map(\.file) == ["k-overview.jpg", "d2-a.jpg", "d2-b.jpg", "o1-a.jpg", "d3-a.jpg"])
        #expect(sections[1].cards.map(\.file) == ["b-overview.jpg", "d1-a.jpg"])
        #expect(sections[2].cards.map(\.file) == ["o2-a.jpg", "d5-a.jpg"])
        #expect(sections[3].cards.map(\.file) == ["d4-a.jpg"])
        #expect(sections[4].cards.map(\.file) == ["m1-a.jpg"])
    }

    @Test func aCardSaysWhereItBelongsWhatItShowsAndWhenItWasTaken() {
        let kitchen = AnnexContent.sections(record, s)[0].cards
        let second = kitchen[2]
        #expect(second.where == "Cuisine")
        #expect(second.number == 2)
        #expect(second.title == "Rayure")
        #expect(second.context.contains(s.item(.floor)), "\(second.context)")
        #expect(second.meta == ["\(s.photo) 2 / 2", "\(s.capturedOn) 21.10.2025 09:00", "d2-b.jpg"])
        #expect(kitchen[0].number == nil)
        #expect(kitchen[0].title == s.overviewPhotos)

        let bathFinding = AnnexContent.sections(record, s)[1].cards[1]
        #expect(bathFinding.context.contains(s.chargedToTenant), "\(bathFinding.context)")
        // A finding on an object names the object as well as the room.
        let onObject = kitchen[4]
        #expect(onObject.number == 3)
        #expect(onObject.where == "Cuisine · Lave-vaisselle")
    }
}
