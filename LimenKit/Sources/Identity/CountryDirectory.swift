import Foundation

/// A phone region shown in the form, complete with its recognised calling code and flag.
public struct PhoneCountry: Hashable, Sendable, Identifiable {
    public let regionCode: String
    public let callingCode: Int

    public var id: String { regionCode }
    public var flag: String { CountryDirectory.flag(regionCode) }
    public func label(locale: Locale = .current) -> String {
        "\(flag) +\(callingCode) \(CountryDirectory.name(regionCode, locale: locale))"
    }
}

/// An address country, kept independently from the telephone country.
public struct AddressCountry: Hashable, Sendable, Identifiable {
    public let regionCode: String

    public init(_ regionCode: String) { self.regionCode = regionCode }

    public var id: String { regionCode }
    public var flag: String { CountryDirectory.flag(regionCode) }
    public func label(locale: Locale = .current) -> String {
        "\(flag) \(CountryDirectory.name(regionCode, locale: locale))"
    }
}

/// ISO country lists for address and phone pickers.
public enum CountryDirectory {
    /// The two-letter ISO regions the platform knows, which is Java's `Locale.getISOCountries`
    /// in the same spirit: the world's countries and territories, sorted by their English name.
    /// CLDR's exceptional reservations, which `Locale.Region.isoRegions` carries and Java's
    /// `Locale.getISOCountries` does not: the European Union, the Eurozone, the United Nations,
    /// Outlying Oceania, Sark, Kosovo, and six postal islands. Without this the picker offered
    /// "Eurozone" as a country and ran to 261 where the Android list has 249.
    static let cldrOnly: Set<String> = ["AC", "CP", "CQ", "DG", "EA", "EU", "EZ", "IC", "QO", "TA", "UN", "XK"]

    public static let addressCountries: [AddressCountry] = {
        Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy { ("A"..."Z").contains($0) } && !cldrOnly.contains($0) }
            .map(AddressCountry.init)
            .sorted { name($0.regionCode, locale: english) < name($1.regionCode, locale: english) }
    }()

    public static let addressRegions: Set<String> = Set(addressCountries.map(\.regionCode))

    static let english = Locale(identifier: "en")

    public static func name(_ regionCode: String, locale: Locale = .current) -> String {
        let name = locale.localizedString(forRegionCode: regionCode) ?? ""
        return name.isBlank ? regionCode : name
    }

    public static func flag(_ regionCode: String) -> String {
        let region = regionCode.uppercased()
        guard region.count == 2, region.allSatisfy({ ("A"..."Z").contains($0) }) else { return "🌐" }
        return String(region.unicodeScalars.compactMap { UnicodeScalar(0x1F1E6 + ($0.value - 65)) }.map(Character.init))
    }
}

public struct SwissAddressCandidate: Hashable, Sendable, Identifiable {
    public let street: String
    public let flatNumber: String
    public let postalCode: String
    public let city: String
    public let canton: SwissCanton?

    public init(street: String, flatNumber: String, postalCode: String, city: String, canton: SwissCanton? = nil) {
        self.street = street
        self.flatNumber = flatNumber
        self.postalCode = postalCode
        self.city = city
        self.canton = canton
    }

    public var id: String { label }
    public var label: String { "\(street) \(flatNumber), \(postalCode) \(city)" }
}

extension SessionIdentity {
    public func hasRequiredFields() -> Bool {
        // A draft starts with a name. Contacts are optional and remain as entered; a one-part
        // name, foreign address or absent phone must not prevent a factual inspection record.
        fullName.contains(where: \.isLetter) && CountryDirectory.addressRegions.contains(addressCountry) &&
            (postalCode.isBlank || !usesSwissAddress || postalCode.count == 4 && postalCode.allSatisfy(\.isASCIIDigit)) &&
            (phone.isBlank || InternationalPhone.isValid(phone, regionCode: phoneRegion))
    }
}

/// A small, cancellable client for swisstopo's official building-address search. The query is
/// intentionally sent only after three characters and never written to disk outside the protocol.
public enum SwissAddressLookup {
    private static let endpoint = "https://api3.geo.admin.ch/rest/services/ech/SearchServer"
    /// Ephemeral, so nothing this call sends or receives reaches the shared URL cache on disk: the
    /// text typed here is the address of the flat being inspected, and the shared session would
    /// have kept it, and swisstopo's reply, in Library/Caches beside every other app's traffic.
    private static let session = URLSession(configuration: .ephemeral)
    private static let addressLabel = try? NSRegularExpression(pattern: "^(.+?)\\s+(\\d+[\\p{L}\\-/]*)\\s+(\\d{4})\\s+(.+)$")

    /// What a lookup came back with. `failed` is the Android `Result.failed`: the service could not
    /// be reached or answered with an error, which the screens report as a status line, as
    /// distinct from a reachable service that simply knows no such address.
    public struct Result: Equatable, Sendable {
        public var matches: [SwissAddressCandidate] = []
        public var failed = false
        public init(matches: [SwissAddressCandidate] = [], failed: Bool = false) {
            self.matches = matches
            self.failed = failed
        }
    }

    public static func search(_ query: String) async -> [SwissAddressCandidate] {
        await lookup(query).matches
    }

    public static func lookup(_ query: String) async -> Result {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return Result() }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed),
              let url = URL(string: "\(endpoint)?searchText=\(encoded)&type=locations&origins=address") else { return Result() }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let body = String(data: data, encoding: .utf8) else { return Result(failed: true) }
        return Result(matches: parse(body))
    }

    public static func parse(_ body: String) -> [SwissAddressCandidate] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else { return [] }
        var candidates: [SwissAddressCandidate] = []
        for result in results {
            guard let attrs = result["attrs"] as? [String: Any], attrs["origin"] as? String == "address",
                  let rawLabel = attrs["label"] as? String else { continue }
            let label = rawLabel
                .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let regex = addressLabel,
                  let match = regex.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)),
                  match.numberOfRanges == 5 else { continue }
            func group(_ index: Int) -> String {
                Range(match.range(at: index), in: label).map { String(label[$0]) } ?? ""
            }
            let canton = (attrs["detail"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ").last.map(String.init)
                .flatMap(SwissCanton.fromCode)
            candidates.append(SwissAddressCandidate(street: group(1), flatNumber: group(2), postalCode: group(3), city: group(4), canton: canton))
        }
        return Array(candidates.distinct().prefix(6))
    }
}

extension CharacterSet {
    /// RFC 3986 unreserved characters, what Java's URLEncoder leaves alone plus the space as %20.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
