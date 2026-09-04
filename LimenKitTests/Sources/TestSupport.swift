import Foundation
import Testing
@testable import LimenKit

/// A scratch folder per test, removed when the test ends.
func temporaryRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("limen-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func writeText(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

func readText(_ url: URL) -> String {
    String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self)
}

func makeDir(_ url: URL) throws -> URL {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
