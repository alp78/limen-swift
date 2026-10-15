import Foundation
import LimenKit
import UIKit

extension LimenModel {
    // MARK: A record for the smoke

    #if DEBUG
    /// Under `LIMEN_DEMO`, the draft the Android instrumentation seeded before its walk: an entry
    /// in Vaud with its overlay answered, two named parties, one room and the keys card.
    static func seedDemo(into store: Store, prefs: UserDefaults) {
        var p = HandoverProtocol(id: "navigation-draft", kind: .entry, createdEpochMs: 1)
        p.sessionRole = .tenant
        p.sessionName = "Test tenant"
        p.address = "Test street 1"
        p.place = "1000 Test"
        p.objectCanton = .vd
        p.legalOverlay = LegalOverlayRecord().withStatus(.leaseAndLocalTiming, .confirmed).withStatus(.vaudExitReadiness, .confirmed)
        p.handoverDate = "2026-08-18"
        p.handoverTime = "10:00"
        p.contract.conclusionDate = "2026-07-01"
        p.parties = [Party(.tenant, name: "Test tenant"), Party(.landlord, name: "Test landlord")]
        p.rooms = [Room(id: "r1", kind: .room)]
        p.dossier = [.keys]
        p.keyTransfer = .noPhysicalKeys
        try? store.save(p)
        prefs.set(p.id, forKey: keyOpen)
        prefs.set("Tenant", forKey: keyRole)
        prefs.set("Test tenant", forKey: keyName)
    }

/// Under `LIMEN_STORE`, the exit protocol the store screenshots walk. Complete to the last rule
    /// except the two signatures, which the walk draws so the pad and the seal are photographed as
    /// a person actually produces them. The record is NOT opened: the first shot is the landing.
    static func seedStoreScene(into store: Store, prefs: UserDefaults, lang: Lang) {
        let scene = StoreScene.of(lang)
        var p = HandoverProtocol(id: "store-\(lang.rawValue.lowercased())", kind: .exit, createdEpochMs: 1)
        p.sessionRole = .landlord
        p.sessionName = scene.representative
        p.address = scene.street
        p.place = scene.place
        p.objectCanton = scene.canton
        p.objectDetail = scene.floor
        p.handoverDate = "2026-09-10"
        p.handoverTime = "12:00"
        p.contract.conclusionDate = "2021-03-02"
        p.contract.startDate = "2021-04-01"
        p.contract.endDate = "2026-09-30"
        p.contract.noticeDate = "2026-06-27"
        p.parties = [
            Party(.tenant, name: scene.tenant, address: scene.tenantAddress),
            Party(.landlord, name: scene.agency, representedBy: scene.representative, phone: scene.phone),
        ]
        var identity = SessionIdentity()
        identity.company = scene.agency
        identity.street = scene.controllerStreet
        identity.postalCode = scene.controllerPostal
        identity.city = scene.controllerCity
        identity.phone = scene.phone
        p.sessionIdentity = identity
        var controller = ControllerIdentity()
        controller.organisation = scene.agency
        controller.contactName = scene.representative
        controller.street = scene.controllerStreet
        controller.postalCode = scene.controllerPostal
        controller.city = scene.controllerCity
        controller.phone = scene.phone
        p.controllerIdentity = controller
        p.rooms = [
            Room(id: "r1", kind: .hall, inspected: true),
            Room(id: "r2", kind: .livingRoom, inspected: true),
            Room(id: "r3", kind: .kitchen, inspected: true),
            Room(id: "r4", kind: .bathroom, inspected: true),
            Room(id: "r5", kind: .bedroom, inspected: true),
        ]
        p.roomSetupComplete = true
        var defect = Defect(id: "d1")
        defect.roomId = "r3"
        defect.text = scene.defect
        defect.tenantResponse = .disputes
        defect.tenantComment = scene.tenantComment
        defect.reservation = ""
        p.defects = [defect]
        p.dossier = [.contract, .keys]
        p.keys = [KeyCount(.apartment, count: 3), KeyCount(.mailbox, count: 1)]
        p.keyTransfer = .allTransferred
        // Every requirement the canton actually resolves to, rather than a fixed pair: Vaud carries
        // rows Zug does not, and a scene that answered only the shared ones could not be finalized.
        if let overlay = p.resolvedLegalOverlay() {
            var answers = LegalOverlayRecord()
            for requirement in overlay.requirements { answers = answers.withStatus(requirement, .confirmed) }
            p.legalOverlay = answers
        }
        try? store.save(p)
        prefs.set("Landlord", forKey: keyRole)
        prefs.set(scene.representative, forKey: keyName)
        prefs.set(scene.agency, forKey: keyCompany)
        prefs.set(controller.organisation, forKey: keyControllerOrganisation)
        prefs.set(controller.contactName, forKey: keyControllerContact)
        prefs.set(controller.street, forKey: keyControllerStreet)
        prefs.set(controller.postalCode, forKey: keyControllerPostal)
        prefs.set(controller.city, forKey: keyControllerCity)
        prefs.set(controller.phone, forKey: keyControllerPhone)
    }

    static func resetForTests(prefs: UserDefaults, root: URL) {
        for key in [keyDark, keyLang, keyOpen, keyStep, keyRoom, keyDefect, keyRole, keyName, keyCompany,
                    keyControllerOrganisation, keyControllerContact, keyControllerStreet, keyControllerPostal, keyControllerCity, keyControllerEmail, keyControllerPhone,
                    "reusableIdentity", "addressLookupEnabled", "libraryProtectionEnabled"] + prefs.dictionaryRepresentation().keys.filter({ $0.hasPrefix("validInput.") }) {
            prefs.removeObject(forKey: key)
        }
        for item in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: item)
        }
    }
    #endif
}
