import Foundation
import Testing
@testable import LimenKit

/// The page-break policy of a panel, case by case as the Android suite states it: heights in,
/// closed segments out, the same on both phones for the same heights.
@Suite struct PaginatorTests {
    private typealias Slot = Paginator.Slot
    private typealias Segment = Paginator.Segment

    private func rows(_ heights: CGFloat...) -> [Slot] { heights.map { Slot($0) } }

    @Test func aPanelThatFitsIsOneSegmentOnTheCurrentPage() {
        let segments = Paginator.segments(rows(30, 30, 30), available: 100, full: 500)
        #expect(segments == [Segment(0, 3, newPageBefore: false, continued: false)])
    }

    @Test func rowsFillThePageGreedilyAndTheRestContinuesOnTheNext() {
        let segments = Paginator.segments(rows(30, 30, 30, 30, 30), available: 95, full: 500)
        #expect(segments == [Segment(0, 3, newPageBefore: false, continued: false), Segment(3, 5, newPageBefore: true, continued: true)])
    }

    @Test func aPanelThatWouldOpenWithOneRowMovesWholeToAFreshPage() {
        let segments = Paginator.segments(rows(30, 30, 30), available: 40, full: 500)
        #expect(segments == [Segment(0, 3, newPageBefore: true, continued: false)])
    }

    @Test func aOneRowPanelOpensWithItsOneRowWhereItFits() {
        let segments = Paginator.segments(rows(30), available: 40, full: 500)
        #expect(segments == [Segment(0, 1, newPageBefore: false, continued: false)])
    }

    @Test func aRowKeptWithItsSuccessorNeverEndsASegment() {
        let list = [Slot(30), Slot(30, keepWithNext: true), Slot(30), Slot(30)]
        let segments = Paginator.segments(list, available: 65, full: 65)
        #expect(segments == [
            Segment(0, 1, newPageBefore: false, continued: false),
            Segment(1, 3, newPageBefore: true, continued: true),
            Segment(3, 4, newPageBefore: true, continued: true),
        ])
    }

    @Test func aPanelLeftWithOneRowAfterItsKeptRowsMoveOpensOnAFreshPageInstead() {
        let list = [Slot(30), Slot(30, keepWithNext: true), Slot(30), Slot(30)]
        #expect(Paginator.segments(list, available: 65, full: 500) == [Segment(0, 4, newPageBefore: true, continued: false)])
    }

    @Test func aKeptRowStillOpensASegmentWhenNothingElseFitsOnAFreshPage() {
        let list = [Slot(30, keepWithNext: true), Slot(600), Slot(30)]
        let segments = Paginator.segments(list, available: 500, full: 500)
        #expect(segments == [
            Segment(0, 1, newPageBefore: false, continued: false),
            Segment(1, 2, newPageBefore: true, continued: true),
            Segment(2, 3, newPageBefore: true, continued: true),
        ])
    }

    @Test func aPanelTallerThanTwoPagesGivesThreeSegmentsTheLaterOnesContinued() {
        let segments = Paginator.segments(rows(200, 200, 200, 200, 200), available: 500, full: 500)
        #expect(segments == [
            Segment(0, 2, newPageBefore: false, continued: false),
            Segment(2, 4, newPageBefore: true, continued: true),
            Segment(4, 5, newPageBefore: true, continued: true),
        ])
    }

    @Test func aRowTallerThanAPageIsPlacedAloneOnAFreshPage() {
        // Only one row would open the panel on the current page, so it opens on a fresh one.
        let segments = Paginator.segments(rows(30, 900, 30), available: 200, full: 500)
        #expect(segments == [
            Segment(0, 1, newPageBefore: true, continued: false),
            Segment(1, 2, newPageBefore: true, continued: true),
            Segment(2, 3, newPageBefore: true, continued: true),
        ])
    }

    @Test func noRowsStillGivesOneSegmentSoAnEmptyPanelDraws() {
        #expect(Paginator.segments([], available: 100, full: 500) == [Segment(0, 0, newPageBefore: false, continued: false)])
        #expect(Paginator.segments([], available: -5, full: 500) == [Segment(0, 0, newPageBefore: true, continued: false)])
    }

    @Test func theSameHeightsBreakInTheSamePlacesTwice() {
        let list = rows(37, 120, 44, 44, 300, 12, 12, 500, 60)
        #expect(Paginator.segments(list, available: 333, full: 1400) == Paginator.segments(list, available: 333, full: 1400))
    }
}
