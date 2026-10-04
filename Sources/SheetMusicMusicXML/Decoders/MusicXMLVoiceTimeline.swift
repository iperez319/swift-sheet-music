import SheetMusicCore
import SheetMusicFoundation

/// Time through one `<measure>` as `<backup>` and `<forward>` move it, and where each voice's last note ended.
///
/// A voice is built from its notes in document order, so a voice that enters partway through the bar — after a
/// `<forward>`, which is how MuseScore writes a second voice that starts late — would otherwise be drawn from beat
/// one. The gap this reports goes in front of the late note as a `.locationShift`, the same jog MSCX's `<location>`
/// produces, which layout and playback already honour. Reference: `MusicXmlParserPass2::measure`, which keeps the
/// same running time and fills a voice's leading gap.
struct MusicXMLVoiceTimeline {
    private struct VoiceKey: Hashable {
        let staffIndex: Int
        let voice: String
    }

    private var cursor = Fraction(numerator: 0, denominator: 1)
    private var voiceEnd: [VoiceKey: Fraction] = [:]

    /// `<forward>` moves time on; `<backup>` moves it back.
    mutating func move(by delta: Fraction) {
        cursor += delta
    }

    /// Place a note that takes `length` of time at the current time in its voice, and move time past it.
    ///
    /// - Returns: How long the voice was silent before the note — time since the voice's previous note ended, or
    ///   since the bar began for its first — or `nil` when the note follows straight on.
    mutating func place(noteLasting length: Fraction, staffIndex: Int, voice: String) -> Fraction? {
        let key = VoiceKey(staffIndex: staffIndex, voice: voice)
        let gap = cursor - (voiceEnd[key] ?? Fraction(numerator: 0, denominator: 1))
        cursor += length
        voiceEnd[key] = cursor
        return gap.numerator > 0 ? gap : nil
    }
}
