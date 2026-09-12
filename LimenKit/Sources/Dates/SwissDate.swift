import Foundation

/// Dates are held ISO and written DD/MM/YYYY.
///
/// The record keeps yyyy-MM-dd, because the notice deadlines are computed from a parsed date and
/// because a stored order that sorts is worth more than a stored order that reads. DD/MM/YYYY is
/// the Swiss form convention, so it is what a person types and what the PDF prints; the two meet
/// only here, at the edges.
///
/// Anything already on disk that is not a date passes through untouched. These fields used to
/// accept any text at all, and blanking what somebody wrote in order to enforce a format
/// introduced later would be the worse error of the two.
public enum SwissDate {
    /// The stored value as a person reads it, or the stored value itself when it is not a date.
    public static func display(_ stored: String) -> String {
        guard let date = parse(stored) else { return stored }
        return String(format: "%02d/%02d/%04d", date.day, date.month, date.year)
    }

    public static func parse(_ stored: String) -> LocalDate? { LocalDate.parse(stored) }

    /// The typed form back to storage, or nil while it is incomplete or impossible. A nil is not
    /// an error to report: it is the answer for "17/0" as much as for "31/02/2026", and the field
    /// decides which of the two deserves a mark.
    public static func toStored(_ typed: String) -> String? {
        let digits = digits(in: typed)
        guard digits.count == 8 else { return nil }
        let day = Int(digits.prefix(2)) ?? 0
        let month = Int(digits.dropFirst(2).prefix(2)) ?? 0
        let year = Int(digits.dropFirst(4)) ?? 0
        if year < 1000 { return nil }
        return LocalDate.of(year, month, day)?.isoString
    }

    /// Kotlin's `Char.isDigit` accepts any Unicode decimal digit, and a handset set to an
    /// Arabic-Indic or Devanagari keypad types those: filtering to ASCII dropped the whole entry
    /// and the field stayed empty however carefully the date was typed. Each digit is carried over
    /// to its ASCII twin so everything downstream still sees "0" to "9".
    private static func digits(in raw: String) -> String {
        String(raw.compactMap { character -> Character? in
            guard character.isWholeNumber, let value = character.wholeNumberValue, (0...9).contains(value) else { return nil }
            return Character(String(value))
        })
    }

    /// Digits with the separators put back in, so the field can never hold a shape that is not a
    /// date. Typing is the fast road and the calendar is the sure one; masking is what keeps the
    /// fast road from producing "12 mai" or "5.6.26".
    public static func mask(_ raw: String) -> String {
        let digits = digits(in: raw).prefix(8)
        var out = ""
        for (index, ch) in digits.enumerated() {
            if index == 2 || index == 4 { out.append("/") }
            out.append(ch)
        }
        return out
    }

    // The time of the handover, on the same contract.

    /// Stored as HH:mm on the 24 hour clock, which is how Swiss forms are printed.
    public static func toStoredTime(_ typed: String) -> String? {
        let digits = digits(in: typed)
        guard digits.count == 4 else { return nil }
        let hour = Int(digits.prefix(2)) ?? 0
        let minute = Int(digits.dropFirst(2)) ?? 0
        if hour > 23 || minute > 59 { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    public static func maskTime(_ raw: String) -> String {
        let digits = digits(in: raw).prefix(4)
        var out = ""
        for (index, ch) in digits.enumerated() {
            if index == 2 { out.append(":") }
            out.append(ch)
        }
        return out
    }
}
