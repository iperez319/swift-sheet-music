import SheetMusicCore
import SheetMusicFoundation

/// How a MusicXML `<note><grace/>` becomes a `GraceChord`.
///
/// A grace note takes no time, so it is never appended to its voice: `StaffMeasureBuilder` holds it until the voice's
/// next chord with notes and hangs it there as a before-grace. A grace with no such chord after it in the bar ornaments
/// the chord before it instead, as an after-grace. Reference: `MusicXmlParserPass2::note` and the grace handling in
/// `importmusicxmlpass2.cpp` (`graceNotes`, `isGraceAfter`).
enum MusicXMLGraceDecoder {
    /// A grace chord waiting for the chord it ornaments. Its `GraceType` is only known once that chord is: the
    /// same written grace reads as a before-grace or an after-grace depending on which side of the chord it ends up.
    struct Pending {
        var chord: Chord
        let slash: Bool
        /// The written `<type>`: `16th`, `eighth`, …
        let writtenType: String

        func graceChord(after: Bool) -> GraceChord {
            GraceChord(
                graceType: MusicXMLGraceDecoder.graceType(slash: slash, writtenType: writtenType, after: after),
                duration: chord.duration,
                notes: chord.notes,
            )
        }
    }

    /// MuseScore's reading of a MusicXML grace: a slash makes an acciaccatura, an unslashed eighth an appoggiatura,
    /// and any other value the grace of that length. After-graces take their length from the type alone.
    static func graceType(slash: Bool, writtenType: String, after: Bool) -> GraceType {
        if after {
            switch writtenType {
            case "eighth": return .grace8after
            case "32nd": return .grace32after
            default: return .grace16after
            }
        }
        if slash { return .acciaccatura }
        switch writtenType {
        case "quarter": return .grace4
        case "16th": return .grace16
        case "32nd": return .grace32
        default: return .appoggiatura
        }
    }
}
