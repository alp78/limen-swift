import LimenKit
import UIKit
import XCTest

/// What has to be inside the built app, asserted against the bundle rather than the repository.
/// A resource glob that stops matching, or an asset renamed on the Android side and synced under a
/// new name, is invisible to every other test here: the screens simply draw nothing where the
/// picture was, and the smoke walks past it.
final class BundleTests: XCTestCase {
    /// The Android suite asserts the same 26, which is the point: a canton with no flag is a
    /// canton the person cannot identify beside its name in the grid.
    func testEveryCantonFlagReachedTheBundle() {
        let bundle = Bundle(for: BundleTests.self)
        let app = Bundle.main
        for canton in SwissCanton.allCases {
            let name = "flag-\(canton.code.lowercased())"
            let image = UIImage(named: name, in: app, compatibleWith: nil) ?? UIImage(named: name, in: bundle, compatibleWith: nil)
            XCTAssertNotNil(image, "no \(name) in the bundle")
        }
    }

    /// Apache-2.0 section 4(d) asks for the notice to travel with the distribution, and it is
    /// referenced from the repository root rather than copied under Resources, which is exactly
    /// the arrangement a resource glob can silently stop matching.
    func testTheThirdPartyNoticeReachedTheBundle() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "NOTICE", withExtension: nil), "NOTICE is not in the app bundle")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("libphonenumber"), "the notice does not name the metadata it covers")
    }

    /// The two settings in Project.swift reach the built bundle, which is what the phone's
    /// Settings pane and every crash report read.
    func testTheBundleCarriesTheProjectsVersion() {
        let info = Bundle.main.infoDictionary
        XCTAssertEqual(info?["CFBundleShortVersionString"] as? String, "1.2.5")
        XCTAssertEqual(info?["CFBundleVersion"] as? String, "7")
    }

    func testAuditIdentityAndLocalizedSystemPurposes() throws {
        #if DEBUG
        XCTAssertEqual(Bundle.main.bundleIdentifier, "dev.peringer.limen.audit")
        #endif
        for language in ["en", "fr", "de", "it", "rm"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: language))
            let data = try Data(contentsOf: url)
            let values = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            XCTAssertFalse(values["NSCameraUsageDescription", default: ""].isEmpty)
            XCTAssertFalse(values["NSFaceIDUsageDescription", default: ""].isEmpty)
        }
    }
}
