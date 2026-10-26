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
        // The record itself is the kit's, shared with the UI test and mirrored by Android's
        // StoreScene.kt; only the operator's preferences are the app's to write.
        guard let p = try? StoreScene.seed(into: store, lang: lang) else { return }
        prefs.set("Landlord", forKey: keyRole)
        prefs.set(scene.representative, forKey: keyName)
        prefs.set(scene.agency, forKey: keyCompany)
        prefs.set(p.controllerIdentity.organisation, forKey: keyControllerOrganisation)
        prefs.set(p.controllerIdentity.contactName, forKey: keyControllerContact)
        prefs.set(p.controllerIdentity.street, forKey: keyControllerStreet)
        prefs.set(p.controllerIdentity.postalCode, forKey: keyControllerPostal)
        prefs.set(p.controllerIdentity.city, forKey: keyControllerCity)
        prefs.set(p.controllerIdentity.phone, forKey: keyControllerPhone)
    }

    static func resetForTests(prefs: UserDefaults, root: URL) {
        for key in [keyDark, keyLang, keyOpen, keyStep, keyRoom, keyDefect, keyRole, keyName, keyCompany,
                    keyControllerOrganisation, keyControllerContact, keyControllerStreet, keyControllerPostal, keyControllerCity, keyControllerEmail, keyControllerPhone,
                    "reusableIdentity", "libraryProtectionEnabled"] + prefs.dictionaryRepresentation().keys.filter({ $0.hasPrefix("validInput.") }) {
            prefs.removeObject(forKey: key)
        }
        for item in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: item)
        }
    }
    #endif
}
