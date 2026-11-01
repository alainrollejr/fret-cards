import SwiftUI

enum QuizMode: String, CaseIterable, Codable, Identifiable {
    case staff, fret, all, same, mix
    var id: String { rawValue }
    var title: String {
        switch self {
        case .staff: return "Staff → fretboard"
        case .fret: return "Fretboard → note"
        case .all: return "Find every note"
        case .same: return "Same pitch"
        case .mix: return "Mix all"
        }
    }
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
    var mode = QuizMode.staff
    var maxFret = 4
    var accidentals = false
    var sound = SoundMode.guitar
    var instrument = Instrument.guitar
}

struct Stats: Codable {
    var right = 0
    var total = 0
    var streak = 0
    var best = 0
}

enum CardType: CaseIterable { case staff, fret, all, same }

struct Outcome {
    let ok: Bool
    var tap: Spot?
    var pickedPC: Int?
}

struct Card {
    let type: CardType
    let key: String
    let pref: SpellingPreference
    let spelling: Spelling
    var midi = 0
    var pc = 0
    var spot: Spot?
    var boardMax: Int
    var targets: [Spot] = []
    var found: [Spot] = []
    var wrong: [Spot] = []
    var result: Outcome?

    var isMulti: Bool { type == .all || type == .same }
}

enum Tone { case neutral, good, bad }

@MainActor
final class QuizStore: ObservableObject {
    @Published var settings: Settings {
        didSet {
            let quizChanged = oldValue.mode != settings.mode || oldValue.maxFret != settings.maxFret
                || oldValue.accidentals != settings.accidentals || oldValue.instrument != settings.instrument
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

    static func positions(_ midi: Int, max: Int, instrument: Instrument) -> [Spot] {
        instrument.open.enumerated().compactMap { s, open in
            let f = midi - open
            return f >= 0 && f <= max ? Spot(s: s, f: f) : nil
        }
    }

    /// In standard tuning, unisons across strings need at least frets 0–5.
    static func sameMax(_ settings: Settings) -> Int { max(5, settings.maxFret) }

    private static func pool(_ type: CardType, _ st: Settings) -> [String] {
        let open = st.instrument.open
        let keep = { (midi: Int) in st.accidentals || Theory.isNatural(Theory.pitchClass(midi)) }
        switch type {
        case .staff:
            return (open.last!...(open[0] + st.maxFret)).filter(keep).map { "s\($0)" }
        case .fret:
            return open.indices.flatMap { s in (0...st.maxFret).filter { keep(open[s] + $0) }.map { "f\(s)-\($0)" } }
        case .all:
            return (0..<12).filter { st.accidentals || Theory.isNatural($0) }.map { "a\($0)" }
        case .same:
            let max = sameMax(st)
            return open.indices.flatMap { s in
                (0...max).filter { f in
                    keep(open[s] + f) && positions(open[s] + f, max: max, instrument: st.instrument).count > 1
                }.map { "u\(s)-\($0)" }
            }
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

    private static func makeCard(settings st: Settings, weights: [String: Double], avoid: String?) -> Card {
        let type: CardType = st.mode == .mix ? CardType.allCases.randomElement()! : {
            switch st.mode {
            case .staff: return .staff
            case .fret: return .fret
            case .all: return .all
            default: return .same
            }
        }()
        let pref: SpellingPreference = Bool.random() ? .sharp : .flat
        let key = pick(pool(type, st), weights: weights, settings: st, avoid: avoid)
        let open = st.instrument.open
        let numbers = key.dropFirst().split(separator: "-").compactMap { Int($0) }

        switch type {
        case .staff:
            let midi = numbers[0]
            return Card(type: type, key: key, pref: pref, spelling: Theory.spell(midi, pref), midi: midi, boardMax: st.maxFret)
        case .fret:
            let spot = Spot(s: numbers[0], f: numbers[1])
            let midi = open[spot.s] + spot.f
            return Card(type: type, key: key, pref: pref, spelling: Theory.spell(midi, pref), midi: midi, spot: spot, boardMax: st.maxFret)
        case .all:
            let pc = numbers[0]
            var targets: [Spot] = []
            for s in open.indices {
                for f in 0...st.maxFret where Theory.pitchClass(open[s] + f) == pc { targets.append(Spot(s: s, f: f)) }
            }
            return Card(type: type, key: key, pref: pref, spelling: Theory.spell(pc + 60, pref), pc: pc,
                        boardMax: st.maxFret, targets: targets)
        case .same:
            let spot = Spot(s: numbers[0], f: numbers[1])
            let midi = open[spot.s] + spot.f
            let max = sameMax(st)
            let targets = positions(midi, max: max, instrument: st.instrument).filter { $0.s != spot.s }
            return Card(type: type, key: key, pref: pref, spelling: Theory.spell(midi, pref), midi: midi, spot: spot,
                        boardMax: max, targets: targets)
        }
    }

    // MARK: - Actions

    func newCard() {
        advanceTask?.cancel()
        card = Self.makeCard(settings: settings, weights: weights, avoid: card.key)
    }

    func next() {
        if card.isMulti && card.result == nil {
            finish(ok: false)
        } else {
            newCard()
        }
    }

    func tap(_ spot: Spot) {
        guard card.result == nil else { return }
        let midi = instrument.open[spot.s] + spot.f
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

    func playCurrent() {
        let midi = card.type == .all
            ? card.targets.map { instrument.open[$0.s] + $0.f }.min() ?? 60
            : card.midi
        SoundEngine.shared.play(writtenMidi: midi, mode: settings.sound)
    }

    private func finish(ok: Bool, tap: Spot? = nil, picked: Int? = nil) {
        card.result = Outcome(ok: ok, tap: tap, pickedPC: picked)
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
        if ok {
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

    var cornerLabel: String { settings.maxFret == 4 ? "I" : "0–\(settings.maxFret)" }

    var promptTitle: String {
        switch card.type {
        case .staff: return "Where do you play this note?"
        case .fret: return "Which note is this?"
        case .all: return "Tap every \(card.spelling.name)"
        case .same: return "Tap the same pitch on other strings"
        }
    }

    var promptSubtitle: String {
        let n = card.targets.count
        if card.type == .all {
            return "\(n) spots on frets 0–\(card.boardMax), all strings and octaves"
        }
        return "Marked on the \(describe(card.spot!)). Find \(n) more \(n == 1 ? "spot" : "spots") with this exact pitch on frets 0–\(card.boardMax)"
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
            for p in Self.positions(card.midi, max: card.boardMax, instrument: instrument) {
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
        case .fret:
            break
        }
        return marks
    }

    var feedback: (main: String, hint: String, tone: Tone) {
        let name = card.spelling.name
        if card.isMulti {
            let n = card.targets.count
            let wrong = card.wrong.count
            let wrongText = wrong > 0 ? ", \(wrong) wrong \(wrong == 1 ? "tap" : "taps")" : ""
            guard let r = card.result else { return ("\(card.found.count) of \(n) found\(wrongText)", "", .neutral) }
            if r.ok { return ("All \(n) found, no wrong taps.", "", .good) }
            let missed = n - card.found.count
            return ("\(card.found.count) of \(n) found\(wrongText).", missed > 0 ? "Dashed spots are the ones you missed." : "", .bad)
        }
        guard let r = card.result else { return ("", "", .neutral) }
        let whereText = card.type == .staff
            ? Self.positions(card.midi, max: card.boardMax, instrument: instrument).map(describe).joined(separator: " or ")
            : describe(card.spot!)
        if r.ok { return ("Right, \(name).", whereText, .good) }
        let said = card.type == .staff
            ? r.tap.map { self.name(at: $0) } ?? "?"
            : r.pickedPC.map { Theory.pitchClassNames[$0].joined(separator: " / ") } ?? "?"
        return ("You picked \(said). This is \(name).", whereText, .bad)
    }

    var nextTitle: String {
        if card.result != nil { return "Next card" }
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
        case "a": return "Every " + Theory.pitchClassNames[numbers[0]].joined(separator: "/")
        case "u": return "Same pitch as the " + describe(Spot(s: numbers[0], f: numbers[1]))
        case "s":
            let m = numbers[0]
            let places = Self.positions(m, max: settings.maxFret, instrument: instrument).map(describe).joined(separator: " or ")
            return "\(Theory.pitchClassNames[Theory.pitchClass(m)].joined(separator: "/")) (\(places))"
        default:
            let spot = Spot(s: numbers[0], f: numbers[1])
            return "\(describe(spot)): " + Theory.pitchClassNames[Theory.pitchClass(open[spot.s] + spot.f)].joined(separator: "/")
        }
    }
}
