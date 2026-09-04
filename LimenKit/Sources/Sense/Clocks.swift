import Foundation

/// The legal clocks of the handover, as pure date arithmetic so they can be tested against a
/// calendar.
///
/// The law says "immediately". BGer 4A_388/2013 reports a usual 2 to 3 working-day practice,
/// another view extending to one week, and makes the concrete circumstances decisive. Ten
/// calendar days is a frequent contractual move-in period, not a uniform federal deadline. The
/// deposit's backstop is Art. 257e's one year.
public enum Clocks {
    public static func isWorkingDay(_ d: LocalDate, holidays: Set<LocalDate> = []) -> Bool {
        !d.isWeekend && !holidays.contains(d)
    }

    /// The next working day at or after `d`.
    public static func nextWorkingDay(_ d: LocalDate, holidays: Set<LocalDate> = []) -> LocalDate {
        var x = d
        while !isWorkingDay(x, holidays: holidays) { x = x.plusDays(1) }
        return x
    }

    /// `n` working days after `d`, exclusive of `d` itself.
    public static func addWorkingDays(_ d: LocalDate, _ n: Int, holidays: Set<LocalDate> = []) -> LocalDate {
        var x = d
        var left = n
        while left > 0 {
            x = x.plusDays(1)
            if isWorkingDay(x, holidays: holidays) { left -= 1 }
        }
        return x
    }

    /// A conservative planning target: the second working day after return. It is not a
    /// statutory deadline and does not replace the duty to act immediately.
    public static func exitNoticeSafeBy(_ keysReturned: LocalDate, holidays: Set<LocalDate> = []) -> LocalDate {
        addWorkingDays(keysReturned, 2, holidays: holidays)
    }

    /// The three-working-day practice reference, not a guaranteed legal outer edge.
    public static func exitNoticeLatest(_ keysReturned: LocalDate, holidays: Set<LocalDate> = []) -> LocalDate {
        addWorkingDays(keysReturned, 3, holidays: holidays)
    }

    /// A common contractual ten-day period, shown only as a planning aid.
    public static func entryListBy(_ moveIn: LocalDate) -> LocalDate { moveIn.plusDays(10) }

    /// Art. 257e para 3: if the landlord has asserted no claim legally within one year of the end
    /// of the tenancy, the bank pays the deposit back on the tenant's demand alone.
    public static func depositFreeAfter(_ tenancyEnd: LocalDate) -> LocalDate { tenancyEnd.plusYears(1) }

    /// Art. 78 CO planning aid: shift a Sunday or supplied recognized holiday, but not an ordinary
    /// Saturday. The lease or another agreement can provide otherwise.
    public static func returnDue(_ leaseEnd: LocalDate, holidays: Set<LocalDate> = []) -> LocalDate {
        var date = leaseEnd
        while date.isSunday || holidays.contains(date) { date = date.plusDays(1) }
        return date
    }
}
