import Foundation

enum ChordQuality: String, Codable {
    case major = "M", minor = "m"
}

/// How a chord sounds when played: strummed down-up-down, then optionally broken into an arpeggio.
enum ChordPlayStyle: String, CaseIterable, Codable, Identifiable {
    case strum, both, arp
    var id: String { rawValue }
    var title: String {
        switch self {
        case .strum: return "Strum"
        case .both: return "Strum + arpeggio"
        case .arp: return "Arpeggio"
        }
    }
}

struct Barre: Equatable {
    let f: Int
    let s1: Int // highest string covered (diagram order)
    let s2: Int // lowest string covered
}

/// One way to finger a chord, in diagram order (string 0 = high e). nil = muted, 0 = open.
struct Voicing: Equatable {
    let pc: Int
    let quality: ChordQuality
    let frets: [Int?]
    let fingers: [Int]
    let barre: Barre?
    let place: String

    var key: String { "\(pc)\(quality.rawValue)" }
    var fretted: [Spot] { frets.enumerated().compactMap { s, f in (f ?? 0) > 0 ? Spot(s: s, f: f!) : nil } }

    /// Tab notation, low E first, e.g. x32010.
    var tab: String {
        let t = frets.reversed().map { $0.map(String.init) ?? "x" }
        return frets.contains { ($0 ?? 0) > 9 } ? t.joined(separator: "-") : t.joined()
    }
}

enum Chords {
    static let majorNames = ["C", "D♭", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
    static let minorNames = ["Cm", "C♯m", "Dm", "E♭m", "Em", "Fm", "F♯m", "Gm", "G♯m", "Am", "B♭m", "Bm"]

    static func name(_ pc: Int, _ q: ChordQuality) -> String { q == .major ? majorNames[pc] : minorNames[pc] }

    /// Parses a key like "9m" (pitch class + quality).
    static func parse(_ key: Substring) -> (pc: Int, quality: ChordQuality)? {
        guard let q = key.last.flatMap({ ChordQuality(rawValue: String($0)) }), let pc = Int(key.dropLast()) else { return nil }
        return (pc, q)
    }

    // Shapes below are written low E string first: nil = muted, 0 = open; finger 0 = no finger.
    private struct Shape {
        let pc: Int
        let q: ChordQuality
        let frets: [Int?]
        let fingers: [Int]
    }

    private static let openShapes = [
        Shape(pc: 0, q: .major, frets: [nil, 3, 2, 0, 1, 0], fingers: [0, 3, 2, 0, 1, 0]),
        Shape(pc: 2, q: .major, frets: [nil, nil, 0, 2, 3, 2], fingers: [0, 0, 0, 1, 3, 2]),
        Shape(pc: 4, q: .major, frets: [0, 2, 2, 1, 0, 0], fingers: [0, 2, 3, 1, 0, 0]),
        Shape(pc: 7, q: .major, frets: [3, 2, 0, 0, 0, 3], fingers: [2, 1, 0, 0, 0, 3]),
        Shape(pc: 9, q: .major, frets: [nil, 0, 2, 2, 2, 0], fingers: [0, 0, 1, 2, 3, 0]),
        Shape(pc: 2, q: .minor, frets: [nil, nil, 0, 2, 3, 1], fingers: [0, 0, 0, 2, 3, 1]),
        Shape(pc: 4, q: .minor, frets: [0, 2, 2, 0, 0, 0], fingers: [0, 2, 3, 0, 0, 0]),
        Shape(pc: 9, q: .minor, frets: [nil, 0, 2, 2, 1, 0], fingers: [0, 0, 2, 3, 1, 0]),
    ]

    // Barre shapes, moved up the neck by r frets; the root sits on the low E or A string.
    private struct Movable {
        let name: String
        let base: Int
        let q: ChordQuality
        let frets: [Int?]
        let fingers: [Int]
        let barre: ClosedRange<Int>
    }

    private static let movableShapes = [
        Movable(name: "E", base: 4, q: .major, frets: [0, 2, 2, 1, 0, 0], fingers: [1, 3, 4, 2, 1, 1], barre: 0...5),
        Movable(name: "E", base: 4, q: .minor, frets: [0, 2, 2, 0, 0, 0], fingers: [1, 3, 4, 1, 1, 1], barre: 0...5),
        Movable(name: "A", base: 9, q: .major, frets: [nil, 0, 2, 2, 2, 0], fingers: [0, 1, 2, 3, 4, 1], barre: 1...5),
        Movable(name: "A", base: 9, q: .minor, frets: [nil, 0, 2, 2, 1, 0], fingers: [0, 1, 3, 4, 2, 1], barre: 1...5),
    ]

    /// Every guitar voicing that fits in frets 0–maxFret.
    static func voicings(maxFret: Int) -> [Voicing] {
        var out = openShapes
            .filter { $0.frets.compactMap { $0 }.max()! <= maxFret }
            .map { Voicing(pc: $0.pc, quality: $0.q, frets: $0.frets.reversed(), fingers: $0.fingers.reversed(), barre: nil, place: "open chord") }
        for m in movableShapes {
            for r in stride(from: 1, through: maxFret - 2, by: 1) {
                out.append(Voicing(pc: (m.base + r) % 12, quality: m.q,
                                   frets: m.frets.map { $0.map { $0 + r } }.reversed(),
                                   fingers: m.fingers.reversed(),
                                   barre: Barre(f: r, s1: 5 - m.barre.upperBound, s2: 5 - m.barre.lowerBound),
                                   place: "\(m.name)-shape barre at fret \(r)"))
            }
        }
        return out
    }

    /// Chord keys (e.g. "0M", "9m") available in the range, sorted by root then major first.
    static func keys(maxFret: Int, accidentals: Bool) -> [String] {
        var seen: [(Int, ChordQuality)] = []
        for v in voicings(maxFret: maxFret) where accidentals || Theory.isNatural(v.pc) {
            if !seen.contains(where: { $0 == (v.pc, v.quality) }) { seen.append((v.pc, v.quality)) }
        }
        return seen.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 == .major }.map { "\($0.0)\($0.1.rawValue)" }
    }
}
