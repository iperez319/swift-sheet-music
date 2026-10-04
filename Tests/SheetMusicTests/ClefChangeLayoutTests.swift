import Foundation
@testable import SheetMusicCore
@testable import SheetMusicLayout
import Testing

#if !canImport(CoreGraphics)
    private typealias CGFloat = SheetMusicLayout.CGFloat
#endif

/// A clef change partway through a bar stands in its own room in front of the column it precedes, clear of that
/// column's accidentals and of the column before it — never on the chord (`LayoutEngine+ClefChange.swift`).
@Suite("Clef change layout")
struct ClefChangeLayoutTests {
    private let _installFontMetrics = TestSupport.installFontMetrics

    private static let previousChord = Chord(duration: .quarter, notes: [Note(pitch: 47, tpc: 19)])
    /// B3 and F♯4: the sharp reaches furthest left of the column.
    private static let nextChord = Chord(duration: .quarter, notes: [
        Note(pitch: 59, tpc: 19), Note(pitch: 66, tpc: 20, accidental: .sharp),
    ])

    /// One 4/4 bar in bass clef that turns treble before beat 3, the way httyd bar 14 does.
    private static func score() -> Score {
        let measure = Measure(voices: [Voice(elements: [
            .clef(Clef(concertClefType: "F")),
            .chord(Chord(duration: .quarter, notes: [Note(pitch: 47, tpc: 19)])),
            .chord(previousChord),
            .clef(Clef(concertClefType: "G")),
            .chord(nextChord),
            .chord(Chord(duration: .quarter, notes: [Note(pitch: 59, tpc: 19)])),
        ])])
        return Score(
            division: 480,
            parts: [Part(id: "1", instrument: Instrument(id: "x"), staves: [Staff(measures: [measure])])],
        )
    }

    private struct Placed {
        let clefLeft: CGFloat
        let clefRight: CGFloat
        let previousReach: CGFloat
        let nextInkLeft: CGFloat
        let sp: CGFloat
    }

    private static func place(availableWidth: CGFloat) throws -> Placed {
        let document = LayoutEngine.layout(score: score(), options: .init(), availableWidth: availableWidth)
        let metrics = document.metrics
        let measure = try #require(document.systems.first?.measures.first)
        let clefX = try #require(measure.elements.lazy.compactMap { element -> CGFloat? in
            guard case let .clef(rawType, origin, _) = element, rawType == "G" else { return nil }
            return origin.x
        }.first)
        let previousX = try #require(measure.tickColumns[480])
        let nextX = try #require(measure.tickColumns[960])
        let advance = LayoutEngine.bravuraAdvance(ClefGlyph.glyph(for: .treble).codepoint, metrics: metrics)
        return Placed(
            clefLeft: clefX - advance / 2,
            clefRight: clefX + advance / 2,
            previousReach: previousX + LayoutEngine.columnInk(of: previousChord, metrics: metrics).reach,
            nextInkLeft: nextX - LayoutEngine.inkLeft(of: nextChord, metrics: metrics),
            sp: metrics.sp,
        )
    }

    @Test("stands clear of both columns in a roomy bar", arguments: [400, 800] as [CGFloat])
    func roomy(width: CGFloat) throws {
        let placed = try Self.place(availableWidth: width)
        #expect(abs(placed.nextInkLeft - placed.clefRight - placed.sp * 0.5) < 0.01)
        #expect(placed.clefLeft >= placed.previousReach)
    }

    @Test("opens its own room when the bar is squeezed to its minimum")
    func squeezed() throws {
        let placed = try Self.place(availableWidth: 60)
        #expect(abs(placed.nextInkLeft - placed.clefRight - placed.sp * 0.5) < 0.01)
        #expect(placed.clefLeft - placed.previousReach >= placed.sp * 0.25 - 0.01)
    }
}
