import SwiftUI

enum QuizMode: String, CaseIterable, Codable, Identifiable {
    case staff, fret, all, same, mix, chordName, chordShape
    var id: String { rawValue }
    var title: String {
        switch self {
        case .staff: return "Staff → fretboard"
        case .fret: return "Fretboard → note"
        case .all: return "Find every note"
        case .same: return "Same pitch"
        case .mix: return "Mix notes"
        case .chordName: return "Chord → name"
        case .chordShape: return "Name → chord"
        }
    }
    var isChord: Bool { self == .chordName || self == .chordShape }
}

enum SoundMode: String, CaseIterable, Codable, Identifiable {
    case guitar, tone, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .guitar: return "Plucked string"
        case .tone: return "Simple tone"
        case .off: return "Off"
        }
    }
}

struct Settings: Codable, Equatable {
    static let fretLimit = 15
    static let minSpan = 3 // at least 4 frets on the board

    var mode = QuizMode.staff
    var minFret = 0
    var maxFret = 12
    var layout = FretLayout.horizontal
    var accidentals = false
    var sound = SoundMode.guitar
    var instrument = Instrument.guitar
    var chordPlay = ChordPlayStyle.both

    init() {}

    // Settings saved by an older version lack newer keys; fall back to the defaults for those.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        mode = (try? c.decodeIfPresent(QuizMode.self, forKey: .mode)) ?? d.mode
        minFret = (try? c.decodeIfPresent(Int.self, forKey: .minFret)) ?? d.minFret
        maxFret = (try? c.decodeIfPresent(Int.self, forKey: .maxFret)) ?? d.maxFret
        layout = (try? c.decodeIfPresent(FretLayout.self, forKey: .layout)) ?? d.layout
        accidentals = (try? c.decodeIfPresent(Bool.self, forKey: .accidentals)) ?? d.accidentals
        sound = (try? c.decodeIfPresent(SoundMode.self, forKey: .sound)) ?? d.sound
        instrument = (try? c.decodeIfPresent(Instrument.self, forKey: .instrument)) ?? d.instrument
        chordPlay = (try? c.decodeIfPresent(ChordPlayStyle.self, forKey: .chordPlay)) ?? d.chordPlay
        maxFret = min(Self.fretLimit, max(Self.minSpan, maxFret))
        minFret = min(maxFret - Self.minSpan, max(0, minFret))
    }

    var frets: ClosedRange<Int> { minFret...maxFret }
    var rangeText: String { "\(minFret)–\(maxFret)" }
}

struct Stats: Codable {
    var right = 0
    var total = 0
    var streak = 0
    var best = 0
}

enum CardType { case staff, fret, all, same, chordName, chordShape }

struct Outcome {
    let ok: Bool
    var tap: Spot?
    var pickedPC: Int?
    var pickedChord: String?
    var voicing: Voicing? // the shape shown after a Name → chord answer
}

struct ChordCard {
    let pc: Int
    let quality: ChordQuality
    let voicings: [Voicing]
    let voicing: Voicing // the one shown or played
    var key: String { "\(pc)\(quality.rawValue)" }
    var name: String { Chords.name(pc, quality) }
}

struct Card {
    let type: CardType
    let key: String
    let pref: SpellingPreference
    let spelling: Spelling
    var midi = 0
    var pc = 0
    var spot: Spot?
    var boardMin: Int
    var boardMax: Int
    var targets: [Spot] = []
    var found: [Spot] = []
    var wrong: [Spot] = []
    var result: Outcome?
    var chord: ChordCard?
    var selection: [Spot] = []

    var isMulti: Bool { type == .all || type == .same }
    var frets: ClosedRange<Int> { boardMin...boardMax }
    var isChord: Bool { type == .chordName || type == .chordShape }
}

enum Tone { case neutral, good, bad }

@MainActor
final class QuizStore: ObservableObject {
    @Published var settings: Settings {
        didSet {
            let quizChanged = oldValue.mode != settings.mode || oldValue.frets != settings.frets
                || oldValue.accidentals != settings.accidentals || oldValue.instrument != settings.instrument
            if oldValue.chordPlay != settings.chordPlay, card.isChord { playCurrent() }
            save()
            if quizChanged { newCard() }
        }
    }
    @Published private(set) var stats: Stats
    @Published private(set) var card: Card
    private var weights: [String: Double]
    private var advanceTask: Task<Void, Never>?

    private static let storageKey = "fret-cards-v1"

    private struct Saved: Codable {
        var settings: Settings
        var stats: Stats
        var weights: [String: Double]
    }

    init() {
        var saved = Saved(settings: Settings(), stats: Stats(), weights: [:])
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = decoded
        }
        settings = saved.settings
        stats = saved.stats
        weights = saved.weights
        card = Self.makeCard(settings: saved.settings, weights: saved.weights, avoid: nil)
    }

    private func save() {
        let saved = Saved(settings: settings, stats: stats, weights: weights)
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Card pools

    private var instrument: Instrument { settings.instrument }

    static func positions(_ midi: Int, frets: ClosedRange<Int>, instrument: Instrument) -> [Spot] {
        instrument.open.enumerated().compactMap { s, open in
            frets.contains(midi - open) ? Spot(s: s, f: midi - open) : nil
        }
    }

    /// In standard tuning, unisons across strings need at least six frets (e.g. 0–5).
    static func sameFrets(_ st: Settings) -> ClosedRange<Int> {
        let hi = min(Settings.fretLimit, max(st.maxFret, st.minFret + 5))
        return min(st.minFret, hi - 5)...hi
    }

    private static func pool(_ type: CardType, _ st: Settings) -> [String] {
        let open = st.instrument.open
        let keep = { (midi: Int) in st.accidentals || Theory.isNatural(Theory.pitchClass(midi)) }
        switch type {
        case .staff:
            return (open.last!...(open[0] + st.maxFret))
                .filter { keep($0) && !positions($0, frets: st.frets, instrument: st.instrument).isEmpty }
                .map { "s\($0)" }
        case .fret:
            return open.indices.flatMap { s in st.frets.filter { keep(open[s] + $0) }.map { "f\(s)-\($0)" } }
        case .all:
            return (0..<12).filter { st.accidentals || Theory.isNatural($0) }.map { "a\($0)" }
        case .same:
            let frets = sameFrets(st)
            return open.indices.flatMap { s in
                frets.filter { f in
                    keep(open[s] + f) && positions(open[s] + f, frets: frets, instrument: st.instrument).count > 1
                }.map { "u\(s)-\($0)" }
            }
        case .chordName:
            return Chords.keys(minFret: st.minFret, maxFret: st.maxFret, accidentals: st.accidentals).map { "c\($0)" }
        case .chordShape:
            return Chords.keys(minFret: st.minFret, maxFret: st.maxFret, accidentals: st.accidentals).map { "k\($0)" }
        }
    }

    private static func weightKey(_ key: String, _ st: Settings) -> String { "\(st.instrument.rawValue)|\(key)" }

    /// Missed cards get heavier and come back more often; correct answers ease them back down.
    private static func pick(_ keys: [String], weights: [String: Double], settings: Settings, avoid: String?) -> String {
        let candidates = keys.count > 1 ? keys.filter { $0 != avoid } : keys
        let w = candidates.map { weights[weightKey($0, settings)] ?? 1 }
        var r = Double.random(in: 0..<w.reduce(0, +))
        for (k, wk) in zip(candidates, w) {
            r -= wk
            if r <= 0 { return k }
        }
        return candidates.last!
    }

    private static func makeCard(settings st: Settings, weights: [String: Double], avoid: String?, lastVoicing: Voicing? = nil) -> Card {
        // Chord quizzes are guitar-only; on bass, or with no chord in the range, they fall back to reading the staff.
        let noChords = st.instrument != .guitar || pool(.chordName, st).isEmpty
        let mode = st.mode.isChord && noChords ? .staff : st.mode
        let type: CardType = {
            switch mode {
            case .staff: return .staff
            case .fret: return .fret
            case .all: return .all
            case .same: return .same
            case .mix: return [CardType.staff, .fret, .all, .same].randomElement()!
            case .chordName: return .chordName
            case .chordShape: return .chordShape
            }
        }()
        let pref: SpellingPreference = Bool.random() ? .sharp : .flat
        let key = pick(pool(type, st), weights: weights, settings: st, avoid: avoid)
        let open = st.instrument.open
        let numbers = key.dropFirst().split(separator: "-").compactMap { Int($0) }

        switch type {
        case .chordName, .chordShape:
            let (pc, q) = Chords.parse(key.dropFirst())!
            let vs = Chords.voicings(minFret: st.minFret, maxFret: st.maxFret).filter { $0.pc == pc && $0.quality == q }
            // Move around the neck: avoid showing the same shape twice in a row.
            let fresh = vs.count > 1 ? vs.filter { $0 != lastVoicing } : vs
            let chordPref: SpellingPreference = Chords.name(pc, q).contains("♭") ? .flat : .sharp
            return Card(type: type, key: key, pref: chordPref, spelling: Theory.spell(pc + 60, chordPref), pc: pc,
                        boardMin: st.minFret, boardMax: st.maxFret,
                        chord: ChordCard(pc: pc, quality: q, voicings: vs, voicing: fresh.randomElement()!))
        case .staff:
            let midi = numbers[0]
            return Card(type: type, key: key, pref: pref, spelling: Theory.spell(midi, pref), midi: midi, boardMin: st.minFret, boardMax: st.maxFret)
        case .fret:
            let spot = Spot(s: numbers[0], f: numbers[1])
            let midi = open[spot.s] + spot.f
            return Card(type: type, key: key, pref: pref, spelling: Theory.spell(midi, pref), midi: midi, spot: spot, boardMin: st.minFret, boardMax: st.maxFret)
        case .all:
            let pc = numbers[0]
            var targets: [Spot] = []
            for s in open.indices {
                for f in st.frets where Theory.pitchClass(open[s] + f) == pc { targets.append(Spot(s: s, f: f)) }
            }
            return Card(type: type, key: key, pref: pref, spelling: Theory.spell(pc + 60, pref), pc: pc,
                        boardMin: st.minFret, boardMax: st.maxFret, targets: targets)
        case .same:
            let spot = Spot(s: numbers[0], f: numbers[1])
            let midi = open[spot.s] + spot.f
            let frets = sameFrets(st)
            let targets = positions(midi, frets: frets, instrument: st.instrument).filter { $0.s != spot.s }
            return Card(type: type, key: key, pref: pref, spelling: Theory.spell(midi, pref), midi: midi, spot: spot,
                        boardMin: frets.lowerBound, boardMax: frets.upperBound, targets: targets)
        }
    }

    // MARK: - Actions

    func newCard() {
        advanceTask?.cancel()
        card = Self.makeCard(settings: settings, weights: weights, avoid: card.key, lastVoicing: card.chord?.voicing)
    }

    func next() {
        guard card.result == nil else { return newCard() }
        switch card.type {
        case .chordShape: checkChord()
        case .chordName, .all, .same: finish(ok: false)
        default: newCard()
        }
    }

    func tap(_ spot: Spot) {
        guard card.result == nil else { return }
        let midi = instrument.open[spot.s] + spot.f
        if card.type == .chordShape {
            // One note per string: tapping the same spot removes it, another fret moves it.
            guard spot.f > 0 else { return }
            if let i = card.selection.firstIndex(where: { $0.s == spot.s }) {
                let same = card.selection[i] == spot
                card.selection.remove(at: i)
                if same { return }
            }
            card.selection.append(spot)
            SoundEngine.shared.play(writtenMidi: midi, mode: settings.sound)
            return
        }
        SoundEngine.shared.play(writtenMidi: midi, mode: settings.sound)
        if card.isMulti {
            if card.type == .same && spot == card.spot { return }
            if card.found.contains(spot) || card.wrong.contains(spot) { return }
            let match = card.type == .all ? Theory.pitchClass(midi) == card.pc : midi == card.midi
            if match { card.found.append(spot) } else { card.wrong.append(spot) }
            Haptics.tap(match)
            if card.found.count == card.targets.count { finish(ok: card.wrong.isEmpty) }
        } else {
            finish(ok: midi == card.midi, tap: spot)
        }
    }

    func pick(pitchClass pc: Int) {
        guard card.result == nil else { return }
        SoundEngine.shared.play(writtenMidi: card.midi, mode: settings.sound)
        finish(ok: pc == Theory.pitchClass(card.midi), picked: pc)
    }

    func pick(chord key: String) {
        guard card.result == nil, let chord = card.chord else { return }
        playChord(chord.voicing)
        finish(ok: key == chord.key, pickedChord: key)
    }

    /// Accept any voicing of the chord that fits the fret range; otherwise show the closest one.
    private func checkChord() {
        guard let chord = card.chord else { return }
        let sel = card.selection
        let match = chord.voicings.first { v in v.fretted.count == sel.count && v.fretted.allSatisfy(sel.contains) }
        let score = { (v: Voicing) in v.fretted.filter(sel.contains).count * 2 - v.fretted.count }
        let shown = match ?? chord.voicings.max { score($0) < score($1) }!
        playChord(shown)
        finish(ok: match != nil, voicing: shown)
    }

    private func playChord(_ v: Voicing) {
        SoundEngine.shared.playChord(v, instrument: instrument, mode: settings.sound, style: settings.chordPlay)
    }

    func playCurrent() {
        if let chord = card.chord {
            return playChord(card.result?.voicing ?? chord.voicing)
        }
        let midi = card.type == .all
            ? card.targets.map { instrument.open[$0.s] + $0.f }.min() ?? 60
            : card.midi
        SoundEngine.shared.play(writtenMidi: midi, mode: settings.sound)
    }

    private func finish(ok: Bool, tap: Spot? = nil, picked: Int? = nil, pickedChord: String? = nil, voicing: Voicing? = nil) {
        card.result = Outcome(ok: ok, tap: tap, pickedPC: picked, pickedChord: pickedChord, voicing: voicing)
        stats.total += 1
        let wk = Self.weightKey(card.key, settings)
        if ok {
            stats.right += 1
            stats.streak += 1
            stats.best = max(stats.best, stats.streak)
            let w = max(1, (weights[wk] ?? 1) * 0.6)
            weights[wk] = w <= 1.05 ? nil : w
        } else {
            stats.streak = 0
            weights[wk] = min(12, (weights[wk] ?? 1) * 2 + 1)
        }
        Haptics.result(ok)
        save()
        // Chord answers stay up so the fingering can be studied while it plays.
        if ok && !card.isChord {
            advanceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                guard !Task.isCancelled else { return }
                self?.newCard()
            }
        }
    }

    func resetProgress() {
        stats = Stats()
        weights = [:]
        save()
    }

    // MARK: - Text and marks for the views

    func describe(_ spot: Spot) -> String {
        let name = instrument.stringNames[spot.s]
        return spot.f == 0 ? "open \(name) string" : "\(name) string, fret \(spot.f)"
    }

    private func name(at spot: Spot) -> String {
        Theory.spell(instrument.open[spot.s] + spot.f, card.pref).name
    }

    var cornerLabel: String { settings.frets == 0...4 ? "I" : settings.rangeText }

    var promptTitle: String {
        switch card.type {
        case .staff: return "Where do you play this note?"
        case .fret: return "Which note is this?"
        case .all: return "Tap every \(card.spelling.name)"
        case .same: return "Tap the same pitch on other strings"
        case .chordName: return "Which chord is this?"
        case .chordShape: return "Fret \(card.chord!.name)"
        }
    }

    var promptSubtitle: String {
        if let chord = card.chord {
            return "\(chord.quality == .major ? "Major" : "Minor") chord on frets \(card.boardMin)–\(card.boardMax). Tap the fretted notes; open and muted strings need no tap."
        }
        let n = card.targets.count
        if card.type == .all {
            return "\(n) spots on frets \(card.boardMin)–\(card.boardMax), all strings and octaves"
        }
        return "Marked on the \(describe(card.spot!)). Find \(n) more \(n == 1 ? "spot" : "spots") with this exact pitch on frets \(card.boardMin)–\(card.boardMax)"
    }

    var promptMarks: [FretMark] {
        guard card.type == .fret, let spot = card.spot else { return [] }
        let kind: FretMark.Kind = card.result.map { $0.ok ? .good : .bad } ?? .question
        return [FretMark(spot: spot, kind: kind, label: card.result == nil ? "?" : card.spelling.name)]
    }

    var answerMarks: [FretMark] {
        var marks: [FretMark] = []
        let label = card.spelling.name
        switch card.type {
        case .staff:
            guard let r = card.result else { return [] }
            for p in Self.positions(card.midi, frets: card.frets, instrument: instrument) {
                marks.append(FretMark(spot: p, kind: .good, label: label))
            }
            if !r.ok, let t = r.tap { marks.append(FretMark(spot: t, kind: .bad, label: name(at: t))) }
        case .all, .same:
            if card.type == .same, let s = card.spot { marks.append(FretMark(spot: s, kind: .question, label: label)) }
            marks += card.found.map { FretMark(spot: $0, kind: .good, label: label) }
            marks += card.wrong.map { FretMark(spot: $0, kind: .bad, label: name(at: $0)) }
            if card.result != nil {
                marks += card.targets.filter { !card.found.contains($0) }.map { FretMark(spot: $0, kind: .missed, label: label) }
            }
        case .chordShape:
            guard card.result != nil, let v = card.result?.voicing else {
                return card.selection.map { FretMark(spot: $0, kind: .question, label: name(at: $0)) }
            }
            let roots = v.roots(open: instrument.open)
            for p in v.fretted {
                marks.append(FretMark(spot: p, kind: card.selection.contains(p) ? .good : .missed, label: "\(v.fingers[p.s])",
                                      round: true, root: roots.contains(p)))
            }
            marks += card.selection.filter { !v.fretted.contains($0) }.map { FretMark(spot: $0, kind: .bad, label: name(at: $0)) }
        case .fret, .chordName:
            break
        }
        return marks
    }

    /// Kind used to colour the chord diagram on a Chord → name card.
    var chordKind: FretMark.Kind {
        card.result.map { $0.ok ? .good : .bad } ?? .question
    }

    var feedback: (main: String, hint: String, tone: Tone) {
        if let chord = card.chord {
            let shape = { (v: Voicing) in "\(v.tab), \(v.place)" }
            guard let r = card.result else {
                guard card.type == .chordShape, !card.selection.isEmpty else { return ("", "", .neutral) }
                let n = card.selection.count
                return ("\(n) \(n == 1 ? "note" : "notes") placed.", "Tap a note again to remove it.", .neutral)
            }
            let v = r.voicing ?? chord.voicing
            if r.ok { return ("Right, \(chord.name).", shape(v), .good) }
            if card.type == .chordShape {
                return ("\(chord.name) is \(shape(v)).", "Numbers are fingers; dashed spots are the ones you missed.", .bad)
            }
            let said = r.pickedChord.flatMap { Chords.parse($0[...]) }.map { "You picked \(Chords.name($0.pc, $0.quality)). " } ?? ""
            return ("\(said)This is \(chord.name).", shape(v), .bad)
        }
        let name = card.spelling.name
        if card.isMulti {
            let n = card.targets.count
            let wrong = card.wrong.count
            let wrongText = wrong > 0 ? ", \(wrong) wrong \(wrong == 1 ? "tap" : "taps")" : ""
            guard let r = card.result else {
                return ("\(card.found.count) of \(n) found\(wrongText)", card.found.isEmpty && wrong == 0 ? tapHint : "", .neutral)
            }
            if r.ok { return ("All \(n) found, no wrong taps.", "", .good) }
            let missed = n - card.found.count
            return ("\(card.found.count) of \(n) found\(wrongText).", missed > 0 ? "Dashed spots are the ones you missed." : "", .bad)
        }
        guard let r = card.result else { return ("", card.type == .staff ? tapHint : "", .neutral) }
        let whereText = card.type == .staff
            ? Self.positions(card.midi, frets: card.frets, instrument: instrument).map(describe).joined(separator: " or ")
            : describe(card.spot!)
        if r.ok { return ("Right, \(name).", whereText, .good) }
        if card.type == .staff, let tap = r.tap {
            let diff = instrument.open[tap.s] + tap.f - card.midi
            if diff != 0, diff % 12 == 0 {
                let octaves = abs(diff) / 12
                let amount = octaves == 1 ? "an octave" : "\(octaves) octaves"
                return ("Right note, wrong octave: that \(name) is \(amount) \(diff > 0 ? "higher" : "lower").",
                        "This one: \(whereText)", .bad)
            }
        }
        let said = card.type == .staff
            ? r.tap.map { self.name(at: $0) } ?? "?"
            : r.pickedPC.map { Theory.pitchClassNames[$0].joined(separator: " / ") } ?? "?"
        return ("You picked \(said). This is \(name).", whereText, .bad)
    }

    var tapHint: String {
        settings.minFret == 0
            ? "Tap a string between two fret wires. Before the nut is the open string."
            : "Tap a string between two fret wires."
    }

    var nextTitle: String {
        if card.result != nil { return "Next card" }
        if card.type == .chordShape { return card.selection.isEmpty ? "Show answer" : "Check" }
        return card.isMulti ? "Show answer" : "Skip"
    }

    var weakList: [String] {
        let prefix = "\(instrument.rawValue)|"
        return weights.filter { $0.key.hasPrefix(prefix) && $0.value > 1.5 }
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { label(for: String($0.key.dropFirst(prefix.count))) }
    }

    private func label(for key: String) -> String {
        let numbers = key.dropFirst().split(separator: "-").compactMap { Int($0) }
        let open = instrument.open
        switch key.first {
        case "c", "k":
            guard let (pc, q) = Chords.parse(key.dropFirst()) else { return key }
            return key.first == "c" ? "Chord shape: \(Chords.name(pc, q))" : "Fret \(Chords.name(pc, q))"
        case "a": return "Every " + Theory.pitchClassNames[numbers[0]].joined(separator: "/")
        case "u": return "Same pitch as the " + describe(Spot(s: numbers[0], f: numbers[1]))
        case "s":
            let m = numbers[0]
            let places = Self.positions(m, frets: settings.frets, instrument: instrument).map(describe).joined(separator: " or ")
            return "\(Theory.pitchClassNames[Theory.pitchClass(m)].joined(separator: "/")) (\(places))"
        default:
            let spot = Spot(s: numbers[0], f: numbers[1])
            return "\(describe(spot)): " + Theory.pitchClassNames[Theory.pitchClass(open[spot.s] + spot.f)].joined(separator: "/")
        }
    }
}
