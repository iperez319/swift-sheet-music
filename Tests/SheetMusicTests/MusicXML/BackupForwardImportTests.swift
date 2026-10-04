import Foundation
@testable import SheetMusicCore
@testable import SheetMusicMusicXML
import Testing

/// `<backup>` and `<forward>` move the running time through a bar, so a voice that enters late starts where it
/// enters rather than on beat one.
@Suite("Backup and forward MusicXML import")
struct BackupForwardImportTests {
    /// One 4/4 bar of the upper staff (two divisions per quarter): voice 1 fills the bar, then `rest` follows a
    /// `<backup>` to the downbeat.
    static func score(_ rest: String) throws -> Score {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise version="4.0">
          <part-list><score-part id="P1"><part-name>P</part-name></score-part></part-list>
          <part id="P1">
            <measure number="1">
              <attributes><divisions>2</divisions><time><beats>4</beats><beat-type>4</beat-type></time>
                <clef><sign>G</sign><line>2</line></clef></attributes>
              \(note("C", 5, 8, "whole", voice: 1))
              <backup><duration>8</duration></backup>
              \(rest)
            </measure>
          </part>
        </score-partwise>
        """
        return try MusicXMLParser.parse(Data(xml.utf8))
    }

    static func note(_ step: String, _ octave: Int, _ duration: Int, _ type: String, voice: Int) -> String {
        "<note><pitch><step>\(step)</step><octave>\(octave)</octave></pitch>"
            + "<duration>\(duration)</duration><voice>\(voice)</voice><type>\(type)</type></note>"
    }

    static func forward(_ duration: Int) -> String {
        "<forward><duration>\(duration)</duration></forward>"
    }

    static func voices(_ score: Score) -> [Voice] {
        score.parts[0].staves[0].measures[0].voices
    }

    @Test("a voice entering after a forward starts where it enters")
    func aLateVoiceIsShifted() throws {
        let score = try Self.score(
            Self.forward(6) + Self.note("E", 4, 1, "eighth", voice: 2) + Self.note("F", 4, 1, "eighth", voice: 2),
        )
        let voice = try #require(Self.voices(score).last)
        #expect(Array(voice.elements).count == 3)
        guard case let .locationShift(delta) = voice.elements.first else {
            Issue.record("expected a location shift first, got \(String(describing: voice.elements.first))")
            return
        }
        #expect(delta == Fraction(numerator: 3, denominator: 4))
    }

    @Test("a forward between a voice's own notes shifts the note after it")
    func aGapInsideAVoiceIsShifted() throws {
        let score = try Self.score(
            Self.note("E", 4, 2, "quarter", voice: 2) + Self.forward(4) + Self.note("F", 4, 2, "quarter", voice: 2),
        )
        let voice = try #require(Self.voices(score).last)
        let kinds = voice.elements.map { element -> String in
            switch element {
            case .chord: "chord"
            case let .locationShift(delta): "shift \(delta.numerator)/\(delta.denominator)"
            default: "other"
            }
        }
        #expect(kinds == ["chord", "shift 1/2", "chord"])
    }

    @Test("a voice that starts on the downbeat is left alone")
    func anOnTimeVoiceIsUnchanged() throws {
        let score = try Self.score(Self.note("E", 4, 8, "whole", voice: 2))
        let voice = try #require(Self.voices(score).last)
        #expect(!voice.elements.contains { if case .locationShift = $0 { true } else { false } })
    }

    @Test("chord members share their chord's onset")
    func chordMembersTakeNoTime() throws {
        let score = try Self.score(
            Self.note("E", 4, 4, "half", voice: 2)
                + "<note><chord/><pitch><step>G</step><octave>4</octave></pitch>"
                + "<duration>4</duration><voice>2</voice><type>half</type></note>"
                + Self.note("F", 4, 4, "half", voice: 2),
        )
        let voice = try #require(Self.voices(score).last)
        #expect(!voice.elements.contains { if case .locationShift = $0 { true } else { false } })
    }
}
