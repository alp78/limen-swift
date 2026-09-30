import Foundation

/// The scene the store screenshots are taken on, one per language.
///
/// Each language carries its own canton, town, names and telephone, because a German listing
/// showing a Lausanne address reads as the French one with the words swapped. The five below are
/// the scenes the Play listing already ships, transcribed from those screenshots so an agency
/// comparing the two stores sees the same handover in both.
///
/// It lives in the framework rather than in the app because the UI test that walks the shots needs
/// the same strings the seed writes, and a second copy in the test would drift from this one.
/// Debug only: nothing here belongs in a shipped build.
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
    public let defect: String
    public let tenantComment: String

    public static func of(_ lang: Lang) -> StoreScene {
        switch lang {
        case .en:
            return StoreScene(canton: .zg, street: "Alpenstrasse 9", place: "6300 Zug", floor: "2nd floor, left",
                              tenant: "Daniel Foster", tenantAddress: "Chamerstrasse 14, 6300 Zug",
                              agency: "Lakeside Property AG", representative: "Emma Clarke", phone: "+41415551234",
                              controllerStreet: "Baarerstrasse 25", controllerPostal: "6300", controllerCity: "Zug",
                              defect: "Two-centimetre paint chip beside the inner door handle",
                              tenantComment: "Already present when the flat was taken over")
        case .fr:
            return StoreScene(canton: .vd, street: "Rue de Bourg 12", place: "1003 Lausanne", floor: "2e, porte gauche",
                              tenant: "Camille Rochat", tenantAddress: "Chemin de Boissonnet 4, 1010 Lausanne",
                              agency: "Vallonge Immobilier SA", representative: "Sophie Marchand", phone: "+41215551234",
                              controllerStreet: "Avenue de Cour 4", controllerPostal: "1007", controllerCity: "Lausanne",
                              defect: "Éclat de peinture de deux centimètres à côté de la poignée intérieure",
                              tenantComment: "Déjà présent à la reprise du logement")
        case .de:
            return StoreScene(canton: .be, street: "Effingerstrasse 42", place: "3008 Bern", floor: "2. Stock, links",
                              tenant: "Andrea Baumann", tenantAddress: "Waldheimstrasse 12, 3013 Bern",
                              agency: "Aarequai Immobilien AG", representative: "Sandra Keller", phone: "+41315551234",
                              controllerStreet: "Monbijoustrasse 18", controllerPostal: "3011", controllerCity: "Bern",
                              defect: "Zwei Zentimeter grosser Lackabsplitter neben der inneren Türfalle",
                              tenantComment: "Beim Einzug bereits vorhanden")
        case .it:
            return StoreScene(canton: .ti, street: "Via Nassa 18", place: "6900 Lugano", floor: "2o piano, a sinistra",
                              tenant: "Marco Donati", tenantAddress: "Via Zurigo 9, 6900 Lugano",
                              agency: "Verzasca Immobiliare SA", representative: "Chiara Bernasconi", phone: "+41915551234",
                              controllerStreet: "Via Cattori 6", controllerPostal: "6900", controllerCity: "Lugano",
                              defect: "Scheggiatura di vernice di due centimetri accanto alla maniglia interna",
                              tenantComment: "Già presente alla consegna iniziale")
        case .rm:
            return StoreScene(canton: .gr, street: "Via Centrala 12", place: "7130 Ilanz", floor: "2. plaun, a sanestra",
                              tenant: "Anna Casanova", tenantAddress: "Sut Vitg 3, 7130 Ilanz",
                              agency: "Sursilva Immobiglias SA", representative: "Gion Caduff", phone: "+41815551234",
                              controllerStreet: "Via Cadi 5", controllerPostal: "7130", controllerCity: "Ilanz",
                              defect: "Splitter da colur da dus centimeters sper la maniglia interna",
                              tenantComment: "Gia preschent cun l\'entrada")
        }
    }
}
#endif
