import Foundation

/// The scene the store screenshots are taken on, one per language.
///
/// Each language carries its own canton, town, names and telephone, because a German listing
/// showing a Lausanne address reads as the French one with the words swapped. The five below are
/// the scenes Android's `StoreScene.kt` seeds for the Play listing, so an agency comparing the two
/// stores sees the same handover in both: three defects in three rooms, each with one photograph.
///
/// It lives in the framework rather than in the app because the UI test that walks the shots needs
/// the same strings the seed writes, and a second copy in the test would drift from this one. The
/// photographs are free-licence pictures the owner chose on 25 October 2026, after the devices and
/// disks held none of a defect; they are bundled as `store-scene-*.jpg`, which the Release
/// configuration excludes, so nothing here reaches a shipped build. Debug only.
#if DEBUG
public struct StoreScene {
    public let canton: SwissCanton
    public let street: String
    public let place: String
    public let floor: String
    public let tenant: String
    public let tenantAddress: String
    public let agency: String
    public let representative: String
    public let phone: String
    public let controllerStreet: String
    public let controllerPostal: String
    public let controllerCity: String
    /// What lets the representative sign for the agency; a party represented by someone needs one.
    public let authority: String
    /// The kitchen wall's water stain, which the tenant disputes with `tenantComment`.
    public let kitchenStain: String
    public let tenantComment: String
    /// The hole in a bathroom wall tile, charged to the tenant, who fixes it for CHF 180.
    public let bathroomTile: String
    /// The scratches in the living room's parquet, normal wear.
    public let parquetScratches: String

    public static func of(_ lang: Lang) -> StoreScene {
        switch lang {
        case .en:
            return StoreScene(canton: .zg, street: "Alpenstrasse 9", place: "6300 Zug", floor: "2nd floor, left",
                              tenant: "Daniel Foster", tenantAddress: "Chamerstrasse 14, 6300 Zug",
                              agency: "Lakeside Property AG", representative: "Emma Clarke", phone: "+41415551234",
                              controllerStreet: "Baarerstrasse 25", controllerPostal: "6300", controllerCity: "Zug",
                              authority: "Management mandate",
                              kitchenStain: "Water stain 30 x 20 cm on the wall above the worktop, dry to the touch",
                              tenantComment: "The stain was there when I moved in",
                              bathroomTile: "Hole 1 cm across in a wall tile beside the washbasin",
                              parquetScratches: "Scratches 40 cm long in the parquet in front of the balcony door")
        case .fr:
            return StoreScene(canton: .vd, street: "Rue de Bourg 12", place: "1003 Lausanne", floor: "2e, porte gauche",
                              tenant: "Camille Rochat", tenantAddress: "Chemin de Boissonnet 4, 1010 Lausanne",
                              agency: "Vallonge Immobilier SA", representative: "Sophie Marchand", phone: "+41215551234",
                              controllerStreet: "Avenue de Cour 4", controllerPostal: "1007", controllerCity: "Lausanne",
                              authority: "Mandat de gérance",
                              kitchenStain: "Tache d’eau de 30 x 20 cm sur le mur au-dessus du plan de travail, sèche au toucher",
                              tenantComment: "La tache existait quand j’ai pris possession du logement",
                              bathroomTile: "Trou de 1 cm dans un carreau mural à côté du lavabo",
                              parquetScratches: "Rayures de 40 cm sur le parquet devant la porte du balcon")
        case .de:
            return StoreScene(canton: .be, street: "Effingerstrasse 42", place: "3008 Bern", floor: "2. Stock, links",
                              tenant: "Andrea Baumann", tenantAddress: "Waldheimstrasse 12, 3013 Bern",
                              agency: "Aarequai Immobilien AG", representative: "Sandra Keller", phone: "+41315551234",
                              controllerStreet: "Monbijoustrasse 18", controllerPostal: "3011", controllerCity: "Bern",
                              authority: "Verwaltungsmandat",
                              kitchenStain: "Wasserfleck 30 x 20 cm an der Wand über der Arbeitsfläche, trocken",
                              tenantComment: "Der Fleck war beim Einzug schon da",
                              bathroomTile: "Loch von 1 cm in einer Wandplatte neben dem Lavabo",
                              parquetScratches: "40 cm lange Kratzer im Parkett vor der Balkontür")
        case .it:
            return StoreScene(canton: .ti, street: "Via Nassa 18", place: "6900 Lugano", floor: "2o piano, a sinistra",
                              tenant: "Marco Donati", tenantAddress: "Via Zurigo 9, 6900 Lugano",
                              agency: "Verzasca Immobiliare SA", representative: "Chiara Bernasconi", phone: "+41915551234",
                              controllerStreet: "Via Cattori 6", controllerPostal: "6900", controllerCity: "Lugano",
                              authority: "Mandato di gestione",
                              kitchenStain: "Macchia d’acqua di 30 x 20 cm sulla parete sopra il piano di lavoro, asciutta al tatto",
                              tenantComment: "La macchia c’era già alla consegna",
                              bathroomTile: "Foro di 1 cm in una piastrella a parete accanto al lavabo",
                              parquetScratches: "Graffi di 40 cm sul parquet davanti alla porta del balcone")
        case .rm:
            return StoreScene(canton: .gr, street: "Via Centrala 12", place: "7130 Ilanz", floor: "2. plaun, a sanestra",
                              tenant: "Anna Casanova", tenantAddress: "Sut Vitg 3, 7130 Ilanz",
                              agency: "Sursilva Immobiglias SA", representative: "Gion Caduff", phone: "+41815551234",
                              controllerStreet: "Via Cadi 5", controllerPostal: "7130", controllerCity: "Ilanz",
                              authority: "Mandat d’administraziun",
                              kitchenStain: "Macla d’aua da 30 x 20 cm sin la paraid sur la surfatscha da lavur, sitga",
                              tenantComment: "La macla era gia qua cun l’entrada",
                              bathroomTile: "Fora d’1 cm en ina plattina da paraid sper il lavabo",
                              parquetScratches: "Sgrattadas da 40 cm en il parchet davant la porta dal balcun")
        }
    }

    /// The record's id, the same in both stores' seeds.
    public static func id(_ lang: Lang) -> String { "store-\(lang.rawValue.lowercased())" }

    /// The handover moment, 10 September 2026 at noon in Europe/Zurich, which is 10:00 UTC under
    /// summer time; the photographs are taken minutes after it, so the legends read 12:18, 12:31
    /// and 12:44. A plain instant rather than a calendar computation, since the zone lookup and
    /// the date assembly both return optionals and the scene test checks the reading.
    public static let handover = Date(timeIntervalSince1970: 1_789_034_400)

    /// One photograph for one defect: which defect, which bundled picture, how long after the handover.
    public struct Shot: Sendable {
        public let defectId: String
        public let resource: String
        public let minutesAfterHandover: Int

        public var capturedEpochMs: Int64 { Int64(StoreScene.handover.timeIntervalSince1970 * 1000) + Int64(minutesAfterHandover) * 60_000 }
        /// Named as the app names a capture, since the file name prints in the annex legend.
        public var file: String { "\(defectId)-\(capturedEpochMs)-1.jpg" }
    }

    public static let shots = [
        Shot(defectId: "d1", resource: "store-scene-kitchen-wall-water-stain", minutesAfterHandover: 18),
        Shot(defectId: "d2", resource: "store-scene-bathroom-tile-hole", minutesAfterHandover: 31),
        Shot(defectId: "d3", resource: "store-scene-living-room-parquet-scratches", minutesAfterHandover: 44),
    ]

    public static func shot(_ defectId: String) -> Shot? { shots.first { $0.defectId == defectId } }

    /// Builds the record and saves it as a draft complete to the last rule except the two
    /// signatures: the walk draws those on the pad and lets the app finalize, so the ink, the
    /// fingerprint and the legal snapshot are the app's own. The photographs are copied out of
    /// the kit's bundle into the record's folder under the capture names and hashed, and listed
    /// in both `photos` and `photoEvidence`, because the editor's thumbnail strip reads the one
    /// and the fingerprint reads both.
    @discardableResult
    public static func seed(into store: Store, lang: Lang) throws -> HandoverProtocol {
        let scene = of(lang)
        let id = id(lang)
        let photoDir = store.photoDir(id)
        try FileManager.default.createDirectory(at: photoDir, withIntermediateDirectories: true)
        var evidence: [String: PhotoEvidence] = [:]
        for shot in shots {
            guard let source = Bundle.limenKit.url(forResource: shot.resource, withExtension: "jpg") else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: shot.resource])
            }
            let target = photoDir.appendingPathComponent(shot.file)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
            evidence[shot.defectId] = PhotoEvidence(shot.file, sha256: try ProtocolIntegrity.fileHash(target), capturedEpochMs: shot.capturedEpochMs, source: .camera)
        }
        func photographed(_ defect: inout Defect) {
            guard let item = evidence[defect.id] else { return }
            defect.photos = [item.file]
            defect.photoEvidence = [item]
        }

        var p = HandoverProtocol(id: id, kind: .exit, createdEpochMs: 1)
        p.sessionRole = .landlord
        p.sessionName = scene.representative
        let names = scene.representative.split(separator: " ", maxSplits: 1).map(String.init)
        var identity = SessionIdentity()
        identity.firstName = names.first ?? ""
        identity.lastName = names.count > 1 ? names[1] : ""
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
        var tenant = Party(.tenant, name: scene.tenant, address: scene.tenantAddress)
        tenant.id = "tenant"
        var landlord = Party(.landlord, name: scene.agency, representedBy: scene.representative, phone: scene.phone)
        landlord.id = "landlord"
        landlord.agency = scene.agency
        landlord.authority = scene.authority
        p.parties = [tenant, landlord]
        p.rooms = [
            Room(id: "r1", kind: .hall, inspected: true),
            Room(id: "r2", kind: .livingRoom, inspected: true),
            Room(id: "r3", kind: .kitchen, inspected: true),
            Room(id: "r4", kind: .bathroom, inspected: true),
            Room(id: "r5", kind: .bedroom, inspected: true),
        ]
        p.roomSetupComplete = true
        // The tenant's position twice over: in the legacy fields Android's seed writes, which the
        // paper and the annex legend print for a record with one tenant, and in the position map
        // keyed by the tenant's id, which this editor shows for a party that has one.
        var stain = Defect(id: "d1", roomId: "r3", item: .walls, text: scene.kitchenStain, tenantResponse: .disputes, tenantComment: scene.tenantComment)
        stain.participantPositions[tenant.id] = TenantPosition(response: .disputes, comment: scene.tenantComment)
        photographed(&stain)
        var tile = Defect(id: "d2", roomId: "r4", item: .tiles, text: scene.bathroomTile, chargedToTenant: true, fixBy: .tenant, costNote: "CHF 180")
        photographed(&tile)
        var scratches = Defect(id: "d3", roomId: "r2", item: .floor, text: scene.parquetScratches, tenantResponse: .normalWear)
        scratches.participantPositions[tenant.id] = TenantPosition(response: .normalWear, comment: "")
        photographed(&scratches)
        p.defects = [stain, tile, scratches]
        p.dossier = [.contract, .keys]
        p.dossierChosen = true
        p.keys = [KeyCount(.apartment, count: 3), KeyCount(.mailbox, count: 1)]
        p.keyTransfer = .allTransferred
        // Every requirement the canton actually resolves to, rather than a fixed pair: Vaud carries
        // rows Zug does not, and a scene that answered only the shared ones could not be finalized.
        if let overlay = p.resolvedLegalOverlay() {
            var answers = LegalOverlayRecord()
            for requirement in overlay.requirements { answers = answers.withStatus(requirement, .confirmed) }
            p.legalOverlay = answers
        }
        try store.save(p)
        return p
    }
}
#endif
