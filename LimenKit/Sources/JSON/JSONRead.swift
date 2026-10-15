import Foundation

/// Parse the ordered tree directly. A global search for a map name loses nesting and cannot
/// distinguish a real key from quoted testimony. Numeric tokens stay integers, never NSNumber.
extension JSON {
    static func parse(_ data: Data) throws -> JSON {
        guard String(data: data, encoding: .utf8) != nil else { throw ProtocolJSONError.notUTF8 }
        var parser = JSONParser(bytes: Array(data))
        let value = try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.bytes.count else { throw ProtocolJSONError.malformed }
        return value
    }
}

private struct JSONParser {
    let bytes: [UInt8]
    var index = 0

    mutating func whitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }

    mutating func consume(_ byte: UInt8) -> Bool {
        whitespace()
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    mutating func value(depth: Int) throws -> JSON {
        guard depth < 64 else { throw ProtocolJSONError.limit }
        whitespace()
        guard index < bytes.count else { throw ProtocolJSONError.malformed }
        switch bytes[index] {
        case 123:
            index += 1
            var fields: [(String, JSON)] = []
            var keys = Set<String>()
            if consume(125) { return .object(fields) }
            repeat {
                let key = try string()
                guard keys.insert(key).inserted, consume(58) else { throw ProtocolJSONError.malformed }
                fields.append((key, try value(depth: depth + 1)))
                if consume(125) { return .object(fields) }
                guard consume(44) else { throw ProtocolJSONError.malformed }
            } while true
        case 91:
            index += 1
            var items: [JSON] = []
            if consume(93) { return .array(items) }
            repeat {
                items.append(try value(depth: depth + 1))
                if consume(93) { return .array(items) }
                guard consume(44) else { throw ProtocolJSONError.malformed }
            } while true
        case 34: return .string(try string())
        case 116: try literal("true"); return .bool(true)
        case 102: try literal("false"); return .bool(false)
        case 110: try literal("null"); return .null
        default:
            let start = index
            if bytes[index] == 45 { index += 1 }
            let digits = index
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
            guard index > digits, index - digits == 1 || bytes[digits] != 48,
                  let number = Int64(String(decoding: bytes[start..<index], as: UTF8.self)) else {
                throw ProtocolJSONError.malformed
            }
            return .int(number)
        }
    }

    mutating func literal(_ word: String) throws {
        let literal = Array(word.utf8)
        guard index + literal.count <= bytes.count,
              Array(bytes[index..<(index + literal.count)]) == literal else { throw ProtocolJSONError.malformed }
        index += literal.count
    }

    mutating func string() throws -> String {
        whitespace()
        let start = index
        guard consume(34) else { throw ProtocolJSONError.malformed }
        var escaped = false
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if escaped { escaped = false } else if byte == 92 { escaped = true } else if byte == 34 {
                let encoded = Data([91] + bytes[start..<index] + [93])
                guard let result = try JSONSerialization.jsonObject(with: encoded) as? [String], let text = result.first else {
                    throw ProtocolJSONError.malformed
                }
                return text
            }
        }
        throw ProtocolJSONError.malformed
    }
}

enum JSONRead {
    static func object(_ value: JSON, allowed: Set<String>) throws -> [String: JSON] {
        guard case .object(let pairs) = value else { throw ProtocolJSONError.notAnObject }
        for (name, _) in pairs where !allowed.contains(name) { throw ProtocolJSONError.unsupported(name) }
        return Dictionary(uniqueKeysWithValues: pairs)
    }

    static func required(_ values: [String: JSON], _ name: String) throws -> JSON {
        guard let value = values[name] else { throw ProtocolJSONError.missing(name) }
        return value
    }

    static func string(_ value: JSON) throws -> String {
        guard case .string(let text) = value else { throw ProtocolJSONError.wrongType("String") }
        return text
    }

    static func bool(_ value: JSON) throws -> Bool {
        guard case .bool(let boolean) = value else { throw ProtocolJSONError.wrongType("Boolean") }
        return boolean
    }

    static func int64(_ value: JSON) throws -> Int64 {
        guard case .int(let number) = value else { throw ProtocolJSONError.wrongType("Long") }
        return number
    }

    static func int32(_ value: JSON) throws -> Int {
        let number = try int64(value)
        guard Int32(exactly: number) != nil else { throw ProtocolJSONError.wrongType("Int") }
        return Int(number)
    }

    static func array(_ value: JSON) throws -> [JSON] {
        guard case .array(let values) = value else { throw ProtocolJSONError.wrongType("Array") }
        return values
    }

    static func optional<T>(_ value: JSON, decode: (JSON) throws -> T) throws -> T? {
        if case .null = value { return nil }
        return try decode(value)
    }

    static func enumeration<T: RawRepresentable>(_ value: JSON, as type: T.Type) throws -> T where T.RawValue == String {
        try enumValue(string(value), as: type)
    }

    static func enumValue<T: RawRepresentable>(_ name: String, as type: T.Type) throws -> T where T.RawValue == String {
        guard let result = T(rawValue: name) else { throw ProtocolJSONError.unknownEnum(String(describing: type), name) }
        return result
    }

    static func map<K, V>(_ value: JSON, decode: (String, JSON) throws -> (K, V)) throws -> OrderedMap<K, V> {
        guard case .object(let pairs) = value else { throw ProtocolJSONError.notAnObject }
        return try OrderedMap(pairs.map { try decode($0.0, $0.1) })
    }
}
