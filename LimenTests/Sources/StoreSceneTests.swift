import Foundation
import LimenKit
import Testing

/// The scene the store walk relies on is complete to the last rule but the signatures, in every
/// language, before any walk depends on it: Android's `sceneIsComplete`, run here in the app
/// process where the kit's photographs are.
struct StoreSceneTests {
    @Test func theSceneIsCompleteButForTheSignaturesInEveryLanguage() throws {
        for lang in Lang.allCases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("limen-scene-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = Store(root: root)
            let p = try StoreScene.seed(into: store, lang: lang)
            #expect(p.rooms.map(\.kind) == [.hall, .livingRoom, .kitchen, .bathroom, .bedroom], "\(lang)")
            #expect(p.defects.count == 3, "\(lang)")
            #expect(Set(p.defects.map(\.roomId)).count == 3, "\(lang)")
            for defect in p.defects {
                let evidence = try #require(defect.photoEvidence.first, "\(lang) \(defect.id)")
                #expect(defect.photoEvidence.count == 1)
                #expect(defect.photos == [evidence.file], "\(lang) \(defect.id)")
                #expect(evidence.source == .camera)
                #expect(evidence.file == StoreScene.shot(defect.id)?.file)
                #expect(evidence.sha256 == (try ProtocolIntegrity.fileHash(store.photoDir(p.id).appendingPathComponent(evidence.file))), "\(lang) \(defect.id)")
            }
            // The legends read 12:18, 12:31 and 12:44 after a noon handover in Zurich, stamped as
            // the annex stamps a capture.
            let stamp = DateFormatter()
            stamp.locale = Locale(identifier: "en_US_POSIX")
            stamp.calendar = Calendar(identifier: .gregorian)
            stamp.timeZone = TimeZone(identifier: "Europe/Zurich")
            stamp.dateFormat = "dd.MM.yyyy HH:mm"
            #expect(stamp.string(from: StoreScene.handover) == "10.09.2026 12:00")
            let minutes = StoreScene.shots.map { stamp.string(from: Date(timeIntervalSince1970: Double($0.capturedEpochMs) / 1000)) }
            #expect(minutes == ["10.09.2026 12:18", "10.09.2026 12:31", "10.09.2026 12:44"])
            // What the editor shows for the tenant is what the paper prints from the legacy fields.
            for defect in p.defects where defect.tenantResponse != .notStated {
                let position = try #require(defect.participantPositions["tenant"], "\(lang) \(defect.id)")
                #expect(position.response == defect.tenantResponse && position.comment == defect.tenantComment, "\(lang) \(defect.id)")
            }
            let overlay = try #require(p.resolvedLegalOverlay(), "\(lang)")
            #expect(overlay.isComplete(p.legalOverlay), "\(lang)")
            #expect(CompletionRules.partiesRecorded(p), "\(lang)")
            let issues = CompletionRules.protocolCompletionIssues(p, requiredRoles: [.tenant, .landlord], photoDir: store.photoDir(p.id), signatureDir: store.signatureDir(p.id))
            #expect(issues == [.recordOutcomes], "\(lang): \(issues)")
            try EvidenceValidation.requireReadable(p, photoDir: store.photoDir(p.id), signatureDir: store.signatureDir(p.id))
            #expect(store.load(p.id) != nil, "\(lang)")
        }
    }
}
