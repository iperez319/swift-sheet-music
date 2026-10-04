#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import SheetMusicCore
import SheetMusicFoundation

/// A clef change partway through a bar: the room it takes in front of the column it precedes, and where in that
/// room it is drawn.
///
/// MuseScore gives a mid-measure clef a `SegmentType::Clef` segment of its own ahead of the chord segment at the
/// same tick, so the spacer opens a gap for it and the clef never lands on the chord. Here a clef shares its
/// column's tick, so the same room is carved out of the gap BEFORE the column — as a collision floor, the way an
/// accidental's room is (`collisionFloors`) — and the clef is drawn in it, clear of the column's accidentals.
/// A clef at the head of a bar is unaffected: the header schedule already has a column for it.
extension LayoutEngine {
    /// Space between a clef change and the leftmost ink of the column it precedes.
    static let clefChangeTrailingPaddingSp: CGFloat = 0.5
    /// Space between the previous column's ink and a clef change, beyond the 0.35 sp that column's `reach` keeps.
    static let clefChangeLeadingPaddingSp: CGFloat = 0.25

    /// A clef change placed with a provisional x, to be moved in front of its column once every voice of the staff
    /// has placed its chords.
    struct ClefChangeSlot {
        let tick: Int
        /// Index of the provisional element in `out`, or in `invisibleOut` when the clef is hidden.
        let index: Int
        let isVisible: Bool
    }

    /// How far left of its column a chord's or rest's ink reaches: its accidentals, else half its notehead.
    static func inkLeft(of chord: Chord, metrics: StaffMetrics) -> CGFloat {
        max(columnInk(of: chord, metrics: metrics).left, StemGeometry.attachDx(sp: metrics.sp))
    }

    /// What a clef change in front of a column adds to how far that column's ink reaches left: the glyph and the
    /// padding on both sides of it.
    static func clefChangeReach(_ clef: Clef, metrics: StaffMetrics) -> CGFloat {
        clefAdvance(rawType: clef.concertClefType, metrics: metrics)
            + (clefChangeLeadingPaddingSp + clefChangeTrailingPaddingSp) * metrics.sp
    }

    /// Moves each clef change in front of its column: its glyph, centered on the x it is given, ends
    /// `clefChangeTrailingPaddingSp` short of the leftmost ink any voice of the staff draws in that column.
    ///
    /// A clef change with no column after it (one at the very end of the bar) keeps its provisional x.
    static func placeClefChanges(
        _ slots: [ClefChangeSlot],
        inkLeftByTick: [Int: CGFloat],
        tickColumns: [Int: CGFloat],
        metrics: StaffMetrics,
        out: inout [LayoutElement],
        invisibleOut: inout [LayoutElement],
    ) {
        for slot in slots {
            guard let columnX = tickColumns[slot.tick] else { continue }
            let inkLeft = inkLeftByTick[slot.tick] ?? StemGeometry.attachDx(sp: metrics.sp)
            func moved(_ element: LayoutElement) -> LayoutElement {
                guard case let .clef(rawType, origin, anchor) = element else { return element }
                let x = columnX - inkLeft - clefChangeTrailingPaddingSp * metrics.sp
                    - clefAdvance(rawType: rawType, metrics: metrics) / 2
                return .clef(rawType: rawType, origin: CGPoint(x: x, y: origin.y), anchor: anchor)
            }
            if slot.isVisible {
                out[slot.index] = moved(out[slot.index])
            } else {
                invisibleOut[slot.index] = moved(invisibleOut[slot.index])
            }
        }
    }

    private static func clefAdvance(rawType: String, metrics: StaffMetrics) -> CGFloat {
        bravuraAdvance(ClefGlyph.glyph(for: NotatedClef(rawType: rawType)).codepoint, metrics: metrics)
    }
}
