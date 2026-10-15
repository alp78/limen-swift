import Foundation

public enum NumberValidation {
    /// Swiss grouping and the written CHF 2'400.- form, without nonfinite or negative values.
    public static func nonNegativeNumber(_ value: String) -> Double? {
        var normalized = value.filter { !$0.isWhitespace && $0 != "'" && $0 != "’" }
            .replacingOccurrences(of: ",", with: ".").uppercased()
        for prefix in ["CHF", "FR."] where normalized.hasPrefix(prefix) { normalized.removeFirst(prefix.count) }
        for suffix in ["CHF", "FR.", ".-", ".–", "."] where normalized.hasSuffix(suffix) { normalized.removeLast(suffix.count) }
        guard normalized.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let number = Double(normalized), number.isFinite, (0...1_000_000_000_000).contains(number) else { return nil }
        return number
    }
}

public enum RecordInputValidation {
    public static func invalidOptionalDate(_ value: String) -> Bool { !value.isBlank && SwissDate.parse(value) == nil }
    /// LocalTime-compatible ISO input; incomplete text remains a draft instead of being coerced.
    public static func validTime(_ value: String) -> Bool {
        guard value.range(of: "^[0-9]{2}:[0-9]{2}(?::[0-9]{2}(?:\\.[0-9]{1,9})?)?$", options: .regularExpression) != nil else { return false }
        let parts = value.split(separator: ":")
        guard let hour = Int(parts[0]), hour < 24, let minute = Int(parts[1]), minute < 60 else { return false }
        return parts.count == 2 || Double(parts[2]).map { $0 < 60 } == true
    }
}
