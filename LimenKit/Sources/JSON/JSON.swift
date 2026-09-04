import Foundation

/// A JSON tree whose objects keep their field order.
///
/// Foundation's encoders order keys by hash or alphabetically, and neither is what
/// kotlinx.serialization wrote: it writes fields in declaration order. The evidence fingerprint
/// hashes that text, so the order is part of the contract, and this tree is how the port writes
/// it exactly.
public indirect enum JSON: Equatable, Sendable {
    case object([(String, JSON)])
    case array([JSON])
    case string(String)
    case int(Int64)
    case bool(Bool)
    case null

    public static func == (lhs: JSON, rhs: JSON) -> Bool { lhs.compact == rhs.compact }

    /// The compact form kotlinx.serialization's default `Json` writes: no whitespace, strings
    /// escaped for the quote, the backslash and the control characters only, everything else
    /// (accents included) raw UTF-8.
    public var compact: String {
        var out = ""
        write(into: &out)
        return out
    }

    private func write(into out: inout String) {
        switch self {
        case .object(let fields):
            out.append("{")
            for (index, (key, value)) in fields.enumerated() {
                if index > 0 { out.append(",") }
                Self.writeString(key, into: &out)
                out.append(":")
                value.write(into: &out)
            }
            out.append("}")
        case .array(let items):
            out.append("[")
            for (index, item) in items.enumerated() {
                if index > 0 { out.append(",") }
                item.write(into: &out)
            }
            out.append("]")
        case .string(let text):
            Self.writeString(text, into: &out)
        case .int(let value):
            out.append(String(value))
        case .bool(let value):
            out.append(value ? "true" : "false")
        case .null:
            out.append("null")
        }
    }

    /// kotlinx's escape table: the short forms for the five named controls, `\u00xx` in lower
    /// case hex for the rest of the C0 range, and nothing else touched.
    static func writeString(_ text: String, into out: inout String) {
        out.append("\"")
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out.append("\\\"")
            case "\\": out.append("\\\\")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            case "\u{08}": out.append("\\b")
            case "\u{0C}": out.append("\\f")
            default:
                if scalar.value < 0x20 {
                    out.append(String(format: "\\u%04x", scalar.value))
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out.append("\"")
    }
}

/// Builds one object in declaration order, deciding per field whether a default is written.
///
/// kotlinx has two knobs: the encoder's `encodeDefaults`, and per property `@EncodeDefault(NEVER)`,
/// which omits the property when it equals its default whatever the encoder says. The store
/// writes with defaults off; the fingerprint writes with them on. `never` marks the properties
/// the Android model annotates, and a property with no default is written always.
struct ObjectBuilder {
    let encodeDefaults: Bool
    private(set) var fields: [(String, JSON)] = []

    init(encodeDefaults: Bool) { self.encodeDefaults = encodeDefaults }

    mutating func always(_ key: String, _ value: JSON) {
        fields.append((key, value))
    }

    mutating func put<T: Equatable>(_ key: String, _ value: T, default fallback: T, never: Bool = false, _ encode: (T) -> JSON) {
        let isDefault = value == fallback
        if never ? !isDefault : (encodeDefaults || !isDefault) {
            fields.append((key, encode(value)))
        }
    }

    var json: JSON { .object(fields) }
}

/// Reads one object the way kotlinx's `ignoreUnknownKeys` reader does: a missing key takes the
/// default, an unknown key is skipped, a wrong type or an unknown enum name refuses the file.
struct ObjectReader {
    let dictionary: [String: Any]

    init(_ any: Any) throws {
        guard let dictionary = any as? [String: Any] else { throw ProtocolJSONError.notAnObject }
        self.dictionary = dictionary
    }

    func string(_ key: String, default fallback: String = "") throws -> String {
        guard let raw = dictionary[key], !(raw is NSNull) else { return fallback }
        guard let value = raw as? String else { throw ProtocolJSONError.wrongType(key) }
        return value
    }

    func requiredString(_ key: String) throws -> String {
        guard let raw = dictionary[key], !(raw is NSNull) else { throw ProtocolJSONError.missing(key) }
        guard let value = raw as? String else { throw ProtocolJSONError.wrongType(key) }
        return value
    }

    func int(_ key: String, default fallback: Int64 = 0) throws -> Int64 {
        guard let raw = dictionary[key], !(raw is NSNull) else { return fallback }
        guard let number = raw as? NSNumber else { throw ProtocolJSONError.wrongType(key) }
        return number.int64Value
    }

    func requiredInt(_ key: String) throws -> Int64 {
        guard dictionary[key] != nil else { throw ProtocolJSONError.missing(key) }
        return try int(key)
    }

    func bool(_ key: String, default fallback: Bool = false) throws -> Bool {
        guard let raw = dictionary[key], !(raw is NSNull) else { return fallback }
        guard let number = raw as? NSNumber else { throw ProtocolJSONError.wrongType(key) }
        return number.boolValue
    }

    func strings(_ key: String) throws -> [String] {
        guard let raw = dictionary[key], !(raw is NSNull) else { return [] }
        guard let array = raw as? [Any] else { throw ProtocolJSONError.wrongType(key) }
        return try array.map { item in
            guard let text = item as? String else { throw ProtocolJSONError.wrongType(key) }
            return text
        }
    }

    func objects(_ key: String) throws -> [ObjectReader] {
        guard let raw = dictionary[key], !(raw is NSNull) else { return [] }
        guard let array = raw as? [Any] else { throw ProtocolJSONError.wrongType(key) }
        return try array.map(ObjectReader.init)
    }

    func object(_ key: String) throws -> ObjectReader? {
        guard let raw = dictionary[key], !(raw is NSNull) else { return nil }
        return try ObjectReader(raw)
    }

    func enumValue<E: RawRepresentable>(_ key: String, default fallback: E) throws -> E where E.RawValue == String {
        guard let raw = dictionary[key], !(raw is NSNull) else { return fallback }
        return try Self.enumFrom(raw, key)
    }

    func optionalEnum<E: RawRepresentable>(_ key: String) throws -> E? where E.RawValue == String {
        guard let raw = dictionary[key], !(raw is NSNull) else { return nil }
        return try Self.enumFrom(raw, key) as E
    }

    func requiredEnum<E: RawRepresentable>(_ key: String) throws -> E where E.RawValue == String {
        guard let raw = dictionary[key], !(raw is NSNull) else { throw ProtocolJSONError.missing(key) }
        return try Self.enumFrom(raw, key)
    }

    func enums<E: RawRepresentable>(_ key: String) throws -> [E] where E.RawValue == String {
        try strings(key).map { name in
            guard let value = E(rawValue: name) else { throw ProtocolJSONError.unknownEnum(key, name) }
            return value
        }
    }

    /// A JSON object whose keys are enum names, in the order the file holds them. JSONSerialization
    /// hands the object back unordered, so the order is recovered from the raw text by
    /// `ProtocolJSON`, which is why this takes the ordered pairs rather than the dictionary.
    func orderedEnumMap<K: RawRepresentable, V: RawRepresentable>(_ key: String, order: [String: [String]]) throws -> OrderedMap<K, V>
    where K.RawValue == String, V.RawValue == String {
        guard let raw = dictionary[key], !(raw is NSNull) else { return OrderedMap() }
        guard let map = raw as? [String: Any] else { throw ProtocolJSONError.wrongType(key) }
        var result = OrderedMap<K, V>()
        let keys = (order[key] ?? []).filter { map[$0] != nil } + map.keys.filter { !(order[key] ?? []).contains($0) }.sorted()
        for name in keys {
            guard let k = K(rawValue: name) else { throw ProtocolJSONError.unknownEnum(key, name) }
            let v: V = try Self.enumFrom(map[name] ?? NSNull(), key)
            result[k] = v
        }
        return result
    }

    func orderedStringMap<K: RawRepresentable>(_ key: String, order: [String: [String]]) throws -> OrderedMap<K, String> where K.RawValue == String {
        guard let raw = dictionary[key], !(raw is NSNull) else { return OrderedMap() }
        guard let map = raw as? [String: Any] else { throw ProtocolJSONError.wrongType(key) }
        var result = OrderedMap<K, String>()
        let keys = (order[key] ?? []).filter { map[$0] != nil } + map.keys.filter { !(order[key] ?? []).contains($0) }.sorted()
        for name in keys {
            guard let k = K(rawValue: name) else { throw ProtocolJSONError.unknownEnum(key, name) }
            guard let v = map[name] as? String else { throw ProtocolJSONError.wrongType(key) }
            result[k] = v
        }
        return result
    }

    private static func enumFrom<E: RawRepresentable>(_ raw: Any, _ key: String) throws -> E where E.RawValue == String {
        guard let name = raw as? String else { throw ProtocolJSONError.wrongType(key) }
        guard let value = E(rawValue: name) else { throw ProtocolJSONError.unknownEnum(key, name) }
        return value
    }
}

public enum ProtocolJSONError: Error, Equatable {
    case notAnObject
    case missing(String)
    case wrongType(String)
    case unknownEnum(String, String)
    case notUTF8
}
