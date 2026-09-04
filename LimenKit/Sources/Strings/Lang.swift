import Foundation

/// The five languages of the Swiss handover. English is the fallback; Romansh is a first for the
/// portfolio. The RM strings use terminology verified against the canton of Grisons' own tenancy
/// forms (locatur, locatari, contract da locaziun, suttascripziun, autoritad da mediaziun); where
/// no official term exists the wording is coined conservatively and the whole language is marked
/// for review by a native speaker before store release.
///
/// French first, as the Android menu orders them.
public enum Lang: String, CaseIterable, Hashable, Sendable {
    case fr = "Fr"
    case en = "En"
    case de = "De"
    case it = "It"
    case rm = "Rm"

    /// The language a handset that was never asked reads in: its own, when the app carries it.
    /// A Swiss German handset reads German, since iOS does not fall back from gsw on its own.
    public static func `default`(preferred: [String] = Locale.preferredLanguages) -> Lang {
        let code = preferred.first?.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
        switch code {
        case "fr": return .fr
        case "de", "gsw": return .de
        case "it": return .it
        case "rm": return .rm
        default: return .en
        }
    }

    public static func from(_ name: String?) -> Lang {
        allCases.first { $0.rawValue == name } ?? .default()
    }

    /// The name of the language in the language itself, so it never needs translating and is
    /// findable by someone lost in the wrong one.
    public var ownName: String {
        switch self {
        case .en: return "English"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .it: return "Italiano"
        case .rm: return "Rumantsch"
        }
    }

    public var locale: Locale {
        switch self {
        case .en: return Locale(identifier: "en")
        case .fr: return Locale(identifier: "fr_CH")
        case .de: return Locale(identifier: "de_CH")
        case .it: return Locale(identifier: "it_CH")
        case .rm: return Locale(identifier: "rm_CH")
        }
    }
}
