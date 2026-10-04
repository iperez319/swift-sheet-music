import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMusicXML
import Testing

/// `<note><grace/>` takes no time: it hangs on the chord it ornaments rather than taking a slot in its voice.
@Suite("Grace note MusicXML import")
struct GraceImportTests {
    /// One 4/4 bar of the upper staff (two divisions per quarter): `notes`, then `extra`.
    static func score(_ notes: String, extra: String = "") throws -> Score {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list><score-part id="P1"><part-name>P</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>2</divisions><time><beats>4</beats><beat-type>4</beat-type></time>
                <clef><sign>G</sign><line>2</line></clef></attributes>
              \(notes)
              \(extra)
            </measure>
          </part>
        </score-partwise>
        """
        return try MusicXMLParser.parse(Data(xml.utf8))
    }

    static func note(_ step: String, _ octave: Int, _ duration: Int, _ type: String, voice: Int = 1) -> String {
        "<note><pitch><step>\(step)</step><octave>\(octave)</octave></pitch>"
            + "<duration>\(duration)</duration><voice>\(voice)</voice><type>\(type)</type></note>"
    }

    static func rest(_ duration: Int, _ type: String) -> String {
        "<note><rest/><duration>\(duration)</duration><voice>1</voice><type>\(type)</type></note>"
    }

    static func grace(
        _ step: String, _ octave: Int, slash: Bool = true, type: String = "16th", voice: Int = 1, chord: Bool = false,
    ) -> String {
        "<note><grace\(slash ? " slash=\"yes\"" : "")/>\(chord ? "<chord/>" : "")<pitch><step>\(step)</step>"
            + "<octave>\(octave)</octave></pitch><voice>\(voice)</voice><type>\(type)</type></note>"
    }

    static func voices(_ score: Score) -> [Voice] {
        score.parts[0].staves[0].measures[0].voices
    }

    static func chords(_ voice: Voice) -> [Chord] {
        voice.elements.compactMap { if case let .chord(chord) = $0 { chord } else { nil } }
    }

    @Test("graces hang on the next chord, which keeps its own time")
    func gracesMoveOntoTheNextChord() throws {
        let score = try Self.score(
            Self.note("C", 5, 4, "half") + Self.grace("F", 5) + Self.grace("E", 5) + Self.note("D", 5, 4, "half"),
        )
        let chords = Self.chords(Self.voices(score)[0])
        #expect(chords.map { $0.notes.map(\.pitch) } == [[72], [74]])
        #expect(chords.map(\.duration) == [.half, .half])
        let graces = chords[1].graceNotesBefore
        #expect(graces.map { $0.notes.map(\.pitch) } == [[77], [76]])
        #expect(graces.map(\.graceType) == [.acciaccatura, .acciaccatura])
        #expect(graces.map(\.duration) == [.sixteenth, .sixteenth])
        #expect(chords[0].graceNotesBefore.isEmpty && chords[1].graceNotesAfter.isEmpty)
    }

    @Test("a grace chord stays one grace chord")
    func aGraceChordStaysOneChord() throws {
        let score = try Self.score(
            Self.grace("C", 5, slash: false, type: "eighth")
                + Self.grace("E", 5, slash: false, type: "eighth", chord: true) + Self.note("D", 5, 8, "whole"),
        )
        let chords = Self.chords(Self.voices(score)[0])
        #expect(chords.count == 1)
        #expect(chords[0].graceNotesBefore.map { $0.notes.map(\.pitch) } == [[72, 76]])
        #expect(chords[0].graceNotesBefore.map(\.graceType) == [.appoggiatura])
    }

    @Test("a grace before a rest waits for the next chord with notes")
    func aGraceSkipsARest() throws {
        let score = try Self.score(
            Self.grace("E", 5) + Self.rest(4, "half") + Self.note("D", 5, 4, "half"),
        )
        let chords = Self.chords(Self.voices(score)[0])
        #expect(chords.map { $0.notes.map(\.pitch) } == [[], [74]])
        #expect(chords[1].graceNotesBefore.map { $0.notes.map(\.pitch) } == [[76]])
    }

    @Test("a grace at the end of the bar follows the chord before it")
    func aGraceAtTheEndOfTheBarIsAnAfterGrace() throws {
        let score = try Self.score(Self.note("C", 5, 8, "whole") + Self.grace("B", 4))
        let chords = Self.chords(Self.voices(score)[0])
        #expect(chords.count == 1)
        #expect(chords[0].graceNotesAfter.map { $0.notes.map(\.pitch) } == [[71]])
        #expect(chords[0].graceNotesAfter.map(\.graceType) == [.grace16after])
    }

    @Test("unslashed graces take their written length", arguments: [
        ("quarter", GraceType.grace4), ("eighth", .appoggiatura), ("16th", .grace16), ("32nd", .grace32),
    ])
    func unslashedGraceTypes(type: String, expected: GraceType) throws {
        let score = try Self.score(Self.grace("E", 5, slash: false, type: type) + Self.note("D", 5, 8, "whole"))
        let chords = Self.chords(Self.voices(score)[0])
        #expect(chords[0].graceNotesBefore.map(\.graceType) == [expected])
    }

    @Test("a voice that opens with a grace keeps its place among the voices")
    func aGraceOpensItsVoice() throws {
        let score = try Self.score(
            Self.grace("F", 4, voice: 2) + Self.note("E", 4, 8, "whole", voice: 2),
            extra: "<backup><duration>8</duration></backup>" + Self.note("C", 5, 8, "whole"),
        )
        let voices = Self.voices(score)
        #expect(voices.count == 2)
        #expect(Self.chords(voices[0]).map { $0.notes.map(\.pitch) } == [[64]])
        #expect(Self.chords(voices[0])[0].graceNotesBefore.map { $0.notes.map(\.pitch) } == [[65]])
        #expect(Self.chords(voices[1]).map { $0.notes.map(\.pitch) } == [[72]])
    }

    /// Voice 2 enters on beat 4 with a grace before its note: the gap goes before the note that takes time, which
    /// carries the grace.
    @Test("a late voice that opens with a grace keeps its gap")
    func aLateVoiceOpeningWithAGrace() throws {
        let score = try Self.score(
            Self.note("C", 5, 8, "whole"),
            extra: "<backup><duration>8</duration></backup><forward><duration>6</duration></forward>"
                + Self.grace("F", 4, voice: 2) + Self.note("E", 4, 2, "quarter", voice: 2),
        )
        let voice = try #require(Self.voices(score).last)
        guard voice.elements.count == 2, case let .locationShift(delta) = voice.elements[0],
              case let .chord(main) = voice.elements[1]
        else {
            Issue.record("expected a location shift then one chord, got \(Array(voice.elements))")
            return
        }
        #expect(delta == Fraction(numerator: 3, denominator: 4))
        #expect(main.notes.map(\.pitch) == [64])
        #expect(main.graceNotesBefore.map { $0.notes.map(\.pitch) } == [[65]])
    }

    @Test("every grace note gets an identity")
    func gracesAreIdentified() throws {
        let score = try Self.score(Self.grace("E", 5) + Self.note("D", 5, 8, "whole"))
        let chord = try #require(Self.chords(Self.voices(score)[0]).first)
        #expect(!chord.graceNotesBefore.hasUnassignedIDs)
        #expect(!chord.graceNotesBefore.contains { $0.notes.hasUnassignedIDs })
    }
}
