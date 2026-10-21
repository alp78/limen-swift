import Foundation

/// Where a panel's rows break across pages. Heights in, index ranges out: the whole page-break
/// policy sits here, away from any graphics context, so it is tested on its own and so both
/// drawing passes, which call it with the same heights, break in the same places.
enum Paginator {
    /// One atomic row of a panel: never split across pages. `keepWithNext` holds it with the row after it.
    struct Slot: Equatable {
        let height: CGFloat
        let keepWithNext: Bool

        init(_ height: CGFloat, keepWithNext: Bool = false) {
            self.height = height
            self.keepWithNext = keepWithNext
        }
    }

    /// The rows `from` until `to` of a panel drawn as one closed panel, on a new page when
    /// `newPageBefore`, headed as a continuation when `continued`.
    struct Segment: Equatable {
        let from: Int
        let to: Int
        let newPageBefore: Bool
        let continued: Bool

        init(_ from: Int, _ to: Int, newPageBefore: Bool, continued: Bool) {
            self.from = from
            self.to = to
            self.newPageBefore = newPageBefore
            self.continued = continued
        }
    }

    /// `available` is the row space left on the current page and `full` the row space of a fresh
    /// page, both with the panel's own chrome already taken off. A panel that would open with
    /// fewer than `minFirstRows` rows moves whole to a fresh page instead of leaving a header
    /// over one line; trailing kept rows move with their successor; a single row taller than a
    /// page is placed anyway, since only a photograph can be and the annex has already sized those.
    static func segments(_ rows: [Slot], available: CGFloat, full: CGFloat, minFirstRows: Int = 2) -> [Segment] {
        if rows.isEmpty { return [Segment(0, 0, newPageBefore: available < 0, continued: false)] }
        var out: [Segment] = []
        var from = 0
        var space = available
        var fresh = false
        while from < rows.count {
            var to = from
            var used: CGFloat = 0
            while to < rows.count, used + rows[to].height <= space {
                used += rows[to].height
                to += 1
            }
            if to == rows.count {
                out.append(Segment(from, to, newPageBefore: fresh, continued: !out.isEmpty))
                break
            }
            // Rows that hold on to their successor leave with it, before the opening is judged, so
            // a panel never opens with the one row a kept group left behind.
            while to - 1 > from, rows[to - 1].keepWithNext { to -= 1 }
            let tooFew = out.isEmpty && to - from < min(minFirstRows, rows.count)
            if to == from || tooFew, !fresh, space < full {
                fresh = true
                space = full
                continue
            }
            if to == from { to = from + 1 }
            out.append(Segment(from, to, newPageBefore: fresh, continued: !out.isEmpty))
            from = to
            fresh = true
            space = full
        }
        return out
    }
}
