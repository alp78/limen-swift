import Foundation
import Testing
@testable import LimenKit

@Suite struct SchemaTests {
    private let minimal = #"{"id":"p","kind":"Entry","createdEpochMs":1}"#

    @Test func nonNullableTypesRejectNullCoercionsFractionsAndOverflow() {
        for field in [#""schema":null"#, #""schema":true"#, #""schema":2147483648"#,
                      #""schema":1.5"#, #""schema":1e0"#, #""oneSided":1"#,
                      #""address":null"#, #""parties":null"#, #""createdEpochMs":9223372036854775808"#,
                      #""createdEpochMs":-9223372036854775809"#, #""createdEpochMs":false"#] {
            let base = field.hasPrefix("\"createdEpochMs\"") ? #"{"id":"p","kind":"Entry",REPLACE}"# : String(minimal.dropLast()) + ",REPLACE}"
            #expect(throws: (any Error).self) { try ProtocolJSON.decode(Data(base.replacingOccurrences(of: "REPLACE", with: field).utf8)) }
        }
    }

    @Test func nullAndMissingHaveDifferentMeaningAndLongsStayExact() throws {
        var p = try ProtocolJSON.decode(Data(minimal.utf8))
        #expect(p.sessionRole == nil)
        p.createdEpochMs = Int64.max
        #expect(try ProtocolJSON.decode(Data(Store.fileText(p).utf8)).createdEpochMs == Int64.max)
        p.createdEpochMs = Int64.min
        #expect(try ProtocolJSON.decode(Data(Store.fileText(p).utf8)).createdEpochMs == Int64.min)
        #expect(throws: ProtocolJSONError.missing("createdEpochMs")) {
            try ProtocolJSON.decode(Data(#"{"id":"p","kind":"Entry"}"#.utf8))
        }
    }

    @Test func duplicateKeysUnknownFieldsAndFutureSchemasAreRecoverablyRejected() {
        for text in [#"{"id":"p","id":"other","kind":"Entry","createdEpochMs":1}"#,
                     #"{"id":"p","kind":"Entry","createdEpochMs":1,"schema":3}"#,
                     #"{"id":"p","kind":"Entry","createdEpochMs":1,"details":{"unknown":"future testimony"}}"#,
                     #"{"id":"p","kind":"Entry","createdEpochMs":1,"defects":[{"id":"d","fixBy":"Future"}]}"#] {
            #expect(throws: ProtocolJSONError.self) { try ProtocolJSON.decode(Data(text.utf8)) }
        }
    }

    @Test func nestedMapOrderSurvivesWhitespaceEscapesAndQuotedMapNames() throws {
        let input = #"""
        { "id": "maps", "kind": "Entry", "createdEpochMs": 1,
          "remarks": "quoted \"checks\": { \"Tenant\": true }", "details": {
            "scopeNotes": { "z\"é": "last alphabetically", "a🗝": "second" },
            "roomPhotos": { "room-z": [{ "file":"photo.png" }], "room-a": [] },
            "estimates": { "defect-z": { "basis":"dated receipt" }, "defect-a": {} },
            "reservations": { "tenant-b":"", "tenant-a":"Reservation" }
          }, "legalOverlay": { "checks": { "VaudExitReadiness":"Confirmed", "LeaseAndLocalTiming":"NotApplicable" },
            "notes": { "InitialRentForm":"unknown", "DepositProof":"unavailable" } },
          "defects": [{"id":"d", "participantPositions": {"tenant-b":{"response":"NormalWear"}, "tenant-a":{"response":"Disputes"}}}]
        }
        """#
        let p = try ProtocolJSON.decode(Data(input.utf8))
        #expect(p.details.scopeNotes.keys == ["z\"é", "a🗝"])
        #expect(p.details.roomPhotos.keys == ["room-z", "room-a"])
        #expect(p.details.estimates.keys == ["defect-z", "defect-a"])
        #expect(p.details.reservations.keys == ["tenant-b", "tenant-a"])
        #expect(p.defects[0].participantPositions.keys == ["tenant-b", "tenant-a"])
        let canonical = ProtocolJSON.encode(p, encodeDefaults: true).compact
        #expect(try ProtocolJSON.encode(ProtocolJSON.decode(Data(Store.fileText(p).utf8)), encodeDefaults: true).compact == canonical)
    }

    @Test func fingerprintedChangingDefaultsArePinnedInStoredFiles() throws {
        var p = HandoverProtocol(id: "defaults", kind: .entry, createdEpochMs: 1)
        p.details.attachments = [SupportingDocument(id: "lease")]
        p.details.estimates["d"] = ReplacementEstimate()
        p.details.legalSnapshot = LegalSnapshot(ruleSetId: "ch-tenancy-2026.2", profile: "FederalAndLease", initialRentFormRule: "NotRequired", requirements: [], sources: [])
        let stored = Store.fileText(p)
        for field in ["mime", "source", "checkedOn"] { #expect(stored.contains("\"\(field)\":")) }
        #expect(try ProtocolJSON.decode(Data(stored.utf8)) == p)
    }

    /// The depth bound is not a size limit and stays; a record file has no size cap any more.
    @Test func nestingDepthHasABoundedFailureAndSizeHasNone() throws {
        let nesting = String(repeating: "[", count: 70) + "0" + String(repeating: "]", count: 70)
        #expect(throws: ProtocolJSONError.limit) { try ProtocolJSON.decode(Data(nesting.utf8)) }
        var p = HandoverProtocol(id: "wide", kind: .entry, createdEpochMs: 1)
        p.remarks = String(repeating: "x", count: 9 * 1024 * 1024)
        let bytes = Data(Store.fileText(p).utf8)
        #expect(bytes.count > 8 * 1024 * 1024)
        #expect(try ProtocolJSON.decode(bytes) == p)
    }
}
