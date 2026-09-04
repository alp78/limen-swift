import Foundation

/// A calendar day with no time and no zone, the shape of `java.time.LocalDate` the clocks and
/// the legal overlay compute with. Arithmetic runs through the proleptic Gregorian calendar in
/// UTC, so a day is a day whatever the handset's zone or the hour of the handover.
public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    /// Trusts its arguments; use `of` for anything typed by a person.
    public init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Nil for a day that does not exist, 31 February as much as 32 January.
    public static func of(_ year: Int, _ month: Int, _ day: Int) -> LocalDate? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        return LocalDate(year, month, day)
    }

    /// ISO 8601, `yyyy-MM-dd`, and nothing else.
    public static func parse(_ text: String) -> LocalDate? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCIIDigit) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        return of(year, month, day)
    }

    public var isoString: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { isoString }

    private var date: Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Self.calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    private static func from(_ date: Date) -> LocalDate {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return LocalDate(parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    public static func today(in zone: TimeZone = .current) -> LocalDate {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = zone
        let parts = local.dateComponents([.year, .month, .day], from: Date())
        return LocalDate(parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    public func plusDays(_ count: Int) -> LocalDate {
        Self.from(Self.calendar.date(byAdding: .day, value: count, to: date) ?? date)
    }

    /// Like Java's, a leap day a year on lands on 28 February.
    public func plusYears(_ count: Int) -> LocalDate {
        Self.from(Self.calendar.date(byAdding: .year, value: count, to: date) ?? date)
    }

    /// Monday is 1, Sunday is 7, as `java.time.DayOfWeek` counts.
    public var dayOfWeek: Int {
        let weekday = Self.calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    public var isWeekend: Bool { dayOfWeek >= 6 }
    public var isSunday: Bool { dayOfWeek == 7 }

    public func isBefore(_ other: LocalDate) -> Bool { self < other }

    /// Days since 1970-01-01, the epoch day the pickers exchange.
    public var epochDay: Int64 { Int64((date.timeIntervalSince1970 / 86_400).rounded(.down)) }

    public static func ofEpochDay(_ epochDay: Int64) -> LocalDate {
        from(Date(timeIntervalSince1970: TimeInterval(epochDay) * 86_400))
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
