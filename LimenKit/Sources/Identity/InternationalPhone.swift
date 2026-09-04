import Foundation

/// Validates and formats contact numbers with Google's national numbering metadata, the same
/// data the Android app reaches through libphonenumber. It is more accurate and more
/// maintainable than a project-owned table of regular expressions and covers shared calling codes.
///
/// The library itself has no platform equivalent on iOS, so the part of it a handover needs is
/// written here: strip what a person types around a number, find the country code, strip the
/// national prefix, and check the national number against the region's patterns and lengths.
public enum InternationalPhone {
    struct NumberType: Decodable {
        let pattern: String
        let lengths: [Int]
        let example: String?
    }

    struct Format: Decodable {
        let pattern: String
        let leadingDigits: String?
        let format: String
        let nationalPrefixFormattingRule: String?
    }

    struct Territory: Decodable {
        let countryCode: Int
        let internationalPrefix: String?
        let nationalPrefix: String?
        let nationalPrefixForParsing: String?
        let nationalPrefixTransformRule: String?
        let nationalPrefixFormattingRule: String?
        let mainCountryForCode: Bool
        let generalPattern: String
        let types: [String: NumberType]
        let formats: [Format]
    }

    public struct Parsed: Hashable, Sendable {
        public let countryCode: Int
        public let nationalNumber: String
    }

    static let territories: [String: Territory] = {
        guard let url = Bundle.limenKit.url(forResource: "PhoneMetadata", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Territory].self, from: data) else { return [:] }
        return decoded
    }()

    private static let regionsByCode: [Int: [String]] = {
        var map: [Int: [String]] = [:]
        for (region, territory) in territories {
            map[territory.countryCode, default: []].append(region)
        }
        // The main country for a shared code comes first, which is the region a bare +1 means.
        for code in map.keys {
            map[code]?.sort { a, b in
                let mainA = territories[a]?.mainCountryForCode ?? false
                let mainB = territories[b]?.mainCountryForCode ?? false
                if mainA != mainB { return mainA }
                return a < b
            }
        }
        return map
    }()

    public static let countries: [PhoneCountry] = {
        territories
            .filter { $0.value.countryCode > 0 }
            .map { PhoneCountry(regionCode: $0.key, callingCode: $0.value.countryCode) }
            .sorted { CountryDirectory.name($0.regionCode, locale: CountryDirectory.english) < CountryDirectory.name($1.regionCode, locale: CountryDirectory.english) }
    }()

    private static let supportedRegions: Set<String> = Set(countries.map(\.regionCode))

    public static func isValid(_ value: String, regionCode: String) -> Bool {
        guard supportedRegions.contains(regionCode), let territory = territories[regionCode],
              let number = parse(value, regionCode: regionCode) else { return false }
        guard number.countryCode == territory.countryCode else { return false }
        return numberType(number.nationalNumber, in: territory) != nil
    }

    /// Store contact numbers in the unambiguous E.164 form, while accepting familiar local entry.
    public static func format(_ value: String, regionCode: String) -> String {
        guard let number = parse(value, regionCode: regionCode) else { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        return "+\(number.countryCode)\(number.nationalNumber)"
    }

    /// The region's fixed-line example, written the way a local would type it.
    public static func example(_ regionCode: String) -> String {
        guard let territory = territories[regionCode], let example = territory.types["fixedLine"]?.example else { return "" }
        return formatNational(example, in: territory)
    }

    // MARK: Parsing

    public static func parse(_ value: String, regionCode: String) -> Parsed? {
        guard let territory = territories[regionCode] else { return nil }
        let raw = extractPossible(value)
        guard !raw.isEmpty else { return nil }
        var digits: String
        var countryCode: Int?
        if raw.hasPrefix("+") {
            digits = String(raw.dropFirst()).filter(\.isASCIIDigit)
            guard let (code, rest) = extractCountryCode(digits) else { return nil }
            countryCode = code
            digits = rest
        } else {
            digits = raw.filter(\.isASCIIDigit)
            if let idd = territory.internationalPrefix, let stripped = strip(prefixPattern: idd, from: digits) {
                guard let (code, rest) = extractCountryCode(stripped) else { return nil }
                countryCode = code
                digits = rest
            }
        }
        let code = countryCode ?? territory.countryCode
        // The region the number turned out to belong to is the one whose national prefix applies.
        let owner = countryCode.flatMap { regionsByCode[$0]?.first }.flatMap { territories[$0] } ?? territory
        let national = stripNationalPrefix(digits, in: owner)
        guard (2...17).contains(national.count) else { return nil }
        return Parsed(countryCode: code, nationalNumber: national)
    }

    /// Everything from the first digit or plus sign to the last digit; anything else a person
    /// types around a number (spaces, dots, brackets, dashes) is dropped.
    private static func extractPossible(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        guard let start = scalars.firstIndex(where: { CharacterSet.decimalDigits.contains($0) || $0 == "+" }) else { return "" }
        guard let end = scalars.lastIndex(where: { CharacterSet.decimalDigits.contains($0) }) else { return "" }
        guard end >= start else { return "" }
        var out = ""
        for scalar in scalars[start...end] {
            if scalar == "+" && out.isEmpty { out.append("+") }
            if let digit = Character(scalar).wholeNumberValue { out.append(String(digit)) }
        }
        return out
    }

    private static func extractCountryCode(_ digits: String) -> (Int, String)? {
        for length in 1...3 where digits.count > length {
            let candidate = Int(digits.prefix(length)) ?? -1
            if regionsByCode[candidate] != nil {
                return (candidate, String(digits.dropFirst(length)))
            }
        }
        return nil
    }

    private static func strip(prefixPattern: String, from digits: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "^(?:\(prefixPattern))"),
              let match = regex.firstMatch(in: digits, range: NSRange(digits.startIndex..., in: digits)),
              let range = Range(match.range, in: digits), !range.isEmpty else { return nil }
        return String(digits[range.upperBound...])
    }

    /// libphonenumber's rule: strip the national prefix unless the number was viable with it and
    /// stops being viable without it.
    private static func stripNationalPrefix(_ digits: String, in territory: Territory) -> String {
        guard let prefixPattern = territory.nationalPrefixForParsing ?? territory.nationalPrefix, !prefixPattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: "^(?:\(prefixPattern))"),
              let match = regex.firstMatch(in: digits, range: NSRange(digits.startIndex..., in: digits)),
              let range = Range(match.range, in: digits) else { return digits }
        let viableBefore = matches(territory.generalPattern, digits)
        let stripped: String
        if let rule = territory.nationalPrefixTransformRule, match.numberOfRanges > 1 {
            stripped = regex.stringByReplacingMatches(in: digits, range: NSRange(digits.startIndex..., in: digits), withTemplate: rule)
        } else {
            stripped = String(digits[range.upperBound...])
        }
        if viableBefore && !matches(territory.generalPattern, stripped) { return digits }
        return stripped
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "^(?:\(pattern))$") else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func numberType(_ national: String, in territory: Territory) -> String? {
        guard matches(territory.generalPattern, national) else { return nil }
        for (name, type) in territory.types {
            if !type.lengths.isEmpty, !type.lengths.contains(national.count) { continue }
            if matches(type.pattern, national) { return name }
        }
        return nil
    }

    // MARK: National format

    static func formatNational(_ national: String, in territory: Territory) -> String {
        for format in territory.formats {
            if let leading = format.leadingDigits {
                guard let regex = try? NSRegularExpression(pattern: "^(?:\(leading))"),
                      regex.firstMatch(in: national, range: NSRange(national.startIndex..., in: national)) != nil else { continue }
            }
            guard let regex = try? NSRegularExpression(pattern: "^(?:\(format.pattern))$"),
                  regex.firstMatch(in: national, range: NSRange(national.startIndex..., in: national)) != nil else { continue }
            var template = format.format
            let rule = format.nationalPrefixFormattingRule ?? territory.nationalPrefixFormattingRule
            if let rule, !rule.isEmpty, let prefix = territory.nationalPrefix {
                let filled = rule.replacingOccurrences(of: "$NP", with: prefix).replacingOccurrences(of: "$FG", with: "$1")
                template = template.replacingOccurrences(of: "$1", with: filled, options: [], range: template.range(of: "$1"))
            }
            return regex.stringByReplacingMatches(in: national, range: NSRange(national.startIndex..., in: national), withTemplate: template)
        }
        return national
    }
}

extension Bundle {
    /// The kit's own bundle, found from a type inside it rather than by identifier.
    public static let limenKit = Bundle(for: LimenKitMarker.self)
}

private final class LimenKitMarker {}
