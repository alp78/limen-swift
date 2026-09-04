import Foundation

/// The canton of the handed-over object, never the participant's contact address.
public enum SwissCanton: String, CaseIterable, Hashable, Sendable {
    case ag = "AG", ai = "AI", ar = "AR", be = "BE", bl = "BL", bs = "BS", fr = "FR", ge = "GE", gl = "GL"
    case gr = "GR", ju = "JU", lu = "LU", ne = "NE", nw = "NW", ow = "OW", sg = "SG", sh = "SH", so = "SO"
    case sz = "SZ", tg = "TG", ti = "TI", ur = "UR", vd = "VD", vs = "VS", zg = "ZG", zh = "ZH"

    public var code: String { rawValue }

    public var label: String {
        switch self {
        case .ag: return "Aargau"
        case .ai: return "Appenzell Innerrhoden"
        case .ar: return "Appenzell Ausserrhoden"
        case .be: return "Bern"
        case .bl: return "Basel-Landschaft"
        case .bs: return "Basel-Stadt"
        case .fr: return "Fribourg"
        case .ge: return "Genève"
        case .gl: return "Glarus"
        case .gr: return "Graubünden"
        case .ju: return "Jura"
        case .lu: return "Luzern"
        case .ne: return "Neuchâtel"
        case .nw: return "Nidwalden"
        case .ow: return "Obwalden"
        case .sg: return "St. Gallen"
        case .sh: return "Schaffhausen"
        case .so: return "Solothurn"
        case .sz: return "Schwyz"
        case .tg: return "Thurgau"
        case .ti: return "Ticino"
        case .ur: return "Uri"
        case .vd: return "Vaud"
        case .vs: return "Valais"
        case .zg: return "Zug"
        case .zh: return "Zürich"
        }
    }

    public static func fromCode(_ code: String) -> SwissCanton? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return allCases.first { $0.code == trimmed }
    }

    private static let romandFrameworkCantons: Set<SwissCanton> = [.fr, .ge, .ju, .ne, .vd, .vs]

    public var supportsRomandFramework: Bool { Self.romandFrameworkCantons.contains(self) }
}

public enum LegalProfile: String, CaseIterable, Hashable, Sendable {
    case federalAndLease = "FederalAndLease"
    case romandContractual = "RomandContractual"
    case vaudRulv2020 = "VaudRulv2020"
    case vaudRulv2026 = "VaudRulv2026"

    public var isVaudRulv: Bool { self == .vaudRulv2020 || self == .vaudRulv2026 }
}

extension HandoverProtocol {
    /// The binding or declared contractual basis that this record actually claims.
    public func legalProfile() -> LegalProfile {
        let date = LocalDate.parse(handoverDate)
        if objectCanton == .vd, let date, !date.isBefore(LocalDate(2026, 7, 1)), date.isBefore(LocalDate(2032, 7, 1)) {
            return .vaudRulv2026
        }
        if objectCanton == .vd, let date, !date.isBefore(LocalDate(2020, 7, 1)), date.isBefore(LocalDate(2026, 7, 1)) {
            return .vaudRulv2020
        }
        return romandFrameworkInLease ? .romandContractual : .federalAndLease
    }
}
