import SheetMusicCore
import SheetMusicFoundation

/// Accumulator for one staff's measure. Collects per-voice element buckets
/// where the "voice" key is an MSCX-style index derived from first-seen
/// MusicXML voice ids. MusicXML assigns global voice ids within a part
/// (e.g. 1 for right hand, 5 for left hand); MSCX uses positional voices
/// per `<voice>` block inside a measure. When a staff has only one MusicXML
/// voice id, everything — including attributes and barlines — ends up in a
/// single MSCX voice. Attributes always land in the first voice index.
struct StaffMeasureBuilder {
    private var voiceIndex: [String: Int] = [:]
    private var voices: [[VoiceElement]] = []
    private var defaultVoiceId: String?
    private var startRepeat = false
    private var endRepeatCount: Int?
    private var trailingBarline: BarLine?
    private var markers: [Marker] = []
    private var jumps: [Jump] = []
    /// System-level elements lifted out during decode (currently
    /// just rehearsal marks; tempo / staff text / swing imports
    /// would feed into this once added). The caller pulls these
    /// out via `build()` and merges them into `Score.systemMeasures`.
    /// `originalStaff` is left nil here and stamped by the caller
    /// once the staff address is known.
    private var systemElements: [PositionedSystemElement] = []
    /// Grace chords not yet hung on a chord, by voice index (`MusicXMLGraceDecoder`).
    private var pendingGraces: [Int: [MusicXMLGraceDecoder.Pending]] = [:]

    /// Result of `build()`: the decoded `Measure` and the system
    /// elements that should be merged into the score-level
    /// `SystemMeasure` for this measure index.
    struct Built {
        let measure: Measure
        let systemElements: [PositionedSystemElement]
    }

    mutating func addMarkers(_ newMarkers: [Marker]) {
        markers.append(contentsOf: newMarkers)
    }

    mutating func addJumps(_ newJumps: [Jump]) {
        jumps.append(contentsOf: newJumps)
    }

    /// Record a rehearsal mark at the start of this measure.
    /// MusicXML's `<direction-type><rehearsal>` doesn't carry a
    /// fractional offset so the position defaults to
    /// `MeasurePosition.start`.
    mutating func addRehearsalMark(_ mark: RehearsalMark) {
        systemElements.append(PositionedSystemElement(
            position: .start,
            element: .rehearsalMark(mark),
        ))
    }

    /// Append to the first voice index (MSCX attributes convention). Lazily
    /// creates the voice 0 bucket if no notes have been seen yet.
    mutating func appendAttribute(_ element: VoiceElement) {
        ensureFirstVoice()
        voices[0].append(element)
    }

    mutating func setDefaultVoice(_ voiceId: String) {
        defaultVoiceId = voiceId
    }

    /// Append a note-sourced element under the MSCX index corresponding to
    /// this MusicXML voice id. The first chord with notes takes the voice's
    /// waiting grace chords as its before-graces.
    mutating func append(_ element: VoiceElement, toVoice voiceId: String) {
        let idx = internVoice(voiceId)
        if case var .chord(chord) = element, !chord.notes.isEmpty,
           let graces = pendingGraces.removeValue(forKey: idx)
        {
            chord.graceNotesBefore = IdentifiedArray(graces.map { $0.graceChord(after: false) })
            voices[idx].append(.chord(chord))
            return
        }
        voices[idx].append(element)
    }

    /// Hold a grace note for the voice's next chord with notes. A grace note
    /// still opens its voice, so voices keep their order of first appearance.
    /// A `<chord/>` grace joins the grace chord before it.
    mutating func appendGrace(
        _ decoded: MusicXMLNoteDecoder.Decoded,
        slash: Bool,
        writtenType: String,
        toVoice voiceId: String,
    ) {
        let idx = internVoice(voiceId)
        switch decoded {
        case let .foldIntoLastChord(note, duration, trailingBreaths):
            if var last = pendingGraces[idx]?.popLast() {
                last.chord.notes = ChordNotes(Array(last.chord.notes) + [note])
                pendingGraces[idx, default: []].append(last)
            } else {
                pendingGraces[idx, default: []].append(MusicXMLGraceDecoder.Pending(
                    chord: Chord(duration: duration, notes: [note]), slash: slash, writtenType: writtenType,
                ))
            }
            voices[idx].append(contentsOf: trailingBreaths.map(VoiceElement.breath))
        case let .new(elements):
            for element in elements {
                if case let .chord(chord) = element, !chord.notes.isEmpty {
                    pendingGraces[idx, default: []].append(MusicXMLGraceDecoder.Pending(
                        chord: chord, slash: slash, writtenType: writtenType,
                    ))
                } else {
                    voices[idx].append(element)
                }
            }
        }
    }

    func elements(forVoice voiceId: String) -> [VoiceElement] {
        guard let idx = voiceIndex[voiceId] else { return [] }
        return voices[idx]
    }

    /// Positional voice index in the eventual built measure for the
    /// given MusicXML voice id. Returns `nil` before any append has
    /// claimed a slot for `voiceId`. Note that voice 0 may still be
    /// reassigned to the first real voice id (see `internVoice`); call
    /// this only after the relevant `append(_:toVoice:)`.
    func voicePositionIndex(forVoice voiceId: String) -> Int? {
        voiceIndex[voiceId]
    }

    mutating func foldIntoLastChord(voice voiceId: String, note: Note, duration: NoteDuration) {
        let idx = internVoice(voiceId)
        var elements = voices[idx]
        if let last = elements.last, case var .chord(chord) = last {
            chord.notes = ChordNotes(Array(chord.notes) + [note])
            elements[elements.count - 1] = .chord(chord)
        } else {
            elements.append(.chord(Chord(duration: duration, notes: [note])))
        }
        voices[idx] = elements
    }

    mutating func apply(barline: MusicXMLBarlineDecoder.Decoded) {
        switch barline.placement {
        case .start:
            if barline.startRepeat { startRepeat = true }
            if let line = barline.inline {
                appendToDefaultVoice(.barLine(line))
            }
        case .middle:
            if let line = barline.inline {
                appendToDefaultVoice(.barLine(line))
            }
        case .end:
            if let count = barline.endRepeatCount { endRepeatCount = count }
            if let line = barline.inline { trailingBarline = line }
        }
    }

    func build() -> Built {
        var final = voices
        // Graces with no chord after them in the bar ornament the chord before
        // them. With no chord there either, they stay ordinary chords.
        for (idx, graces) in pendingGraces.sorted(by: { $0.key < $1.key }) {
            if let host = final[idx].lastIndex(where: {
                if case let .chord(chord) = $0 { !chord.notes.isEmpty } else { false }
            }), case var .chord(chord) = final[idx][host] {
                chord.graceNotesAfter = IdentifiedArray(
                    Array(chord.graceNotesAfter) + graces.map { $0.graceChord(after: true) },
                )
                final[idx][host] = .chord(chord)
            } else {
                final[idx].append(contentsOf: graces.map { .chord($0.chord) })
            }
        }
        if let trailing = trailingBarline {
            if final.isEmpty {
                final.append([])
            }
            let targetIdx: Int
            if let id = defaultVoiceId, let idx = voiceIndex[id] {
                targetIdx = idx
            } else {
                targetIdx = 0
            }
            final[targetIdx].append(.barLine(trailing))
        }
        let builtVoices = final.isEmpty
            ? [Voice(elements: [])]
            : final.map { Voice(elements: $0) }
        let measure = Measure(
            voices: builtVoices,
            startRepeat: startRepeat,
            endRepeatCount: endRepeatCount,
            markers: markers,
            jumps: jumps,
        )
        return Built(measure: measure, systemElements: systemElements)
    }

    // MARK: - private helpers

    private mutating func ensureFirstVoice() {
        if voices.isEmpty {
            voices.append([])
            voiceIndex["__implicit__"] = 0
        }
    }

    private mutating func internVoice(_ voiceId: String) -> Int {
        if let idx = voiceIndex[voiceId] { return idx }
        // If we seeded voice 0 with attributes only and this is the first real
        // voice, adopt that slot instead of creating a new one.
        if voices.count == 1, voiceIndex.values.first == 0,
           voiceIndex["__implicit__"] != nil, voiceIndex.count == 1
        {
            voiceIndex.removeValue(forKey: "__implicit__")
            voiceIndex[voiceId] = 0
            return 0
        }
        let idx = voices.count
        voices.append([])
        voiceIndex[voiceId] = idx
        return idx
    }

    private mutating func appendToDefaultVoice(_ element: VoiceElement) {
        if let id = defaultVoiceId {
            append(element, toVoice: id)
        } else {
            appendAttribute(element)
        }
    }
}
