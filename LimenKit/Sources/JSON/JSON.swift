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

public enum ProtocolJSONError: Error, Equatable {
    case notAnObject
    case missing(String)
    case wrongType(String)
    case unknownEnum(String, String)
    case notUTF8
    case malformed
    case limit
    case unsupported(String)
}
