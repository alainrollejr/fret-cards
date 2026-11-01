import SwiftUI

enum Clef {
    case treble, bass

    /// Diatonic index (octave * 7 + letter) of the bottom staff line: E4 or G2.
    var bottomLine: Int { self == .treble ? 30 : 18 }
    var glyph: String { self == .treble ? "\u{1D11E}" : "\u{1D122}" }
    var name: String { self == .treble ? "treble" : "bass" }
}

enum Instrument: String, CaseIterable, Codable, Identifiable {
    case guitar, bass

    var id: String { rawValue }
    var title: String { self == .guitar ? "Guitar" : "Bass guitar" }

    /// Written pitch (MIDI) of each open string. Index 0 is the top line of the
    /// diagram (highest string). Both instruments are written an octave above
    /// sounding pitch: guitar low E is written E3, bass low E is written E2.
    var open: [Int] { self == .guitar ? [76, 71, 67, 62, 57, 52] : [55, 50, 45, 40] }
    var stringNames: [String] { self == .guitar ? ["high E", "B", "G", "D", "A", "low E"] : ["G", "D", "A", "E"] }
    /// Tab-style labels, highest string first.
    var tabNames: [String] { self == .guitar ? ["e", "B", "G", "D", "A", "E"] : ["G", "D", "A", "E"] }
    var stringWidths: [CGFloat] { self == .guitar ? [1, 1.3, 1.6, 2, 2.4, 2.9] : [1.8, 2.4, 3, 3.6] }
    var clef: Clef { self == .guitar ? .treble : .bass }
}

enum Accidental {
    case natural, sharp, flat

    var symbol: String {
        switch self {
        case .natural: return ""
        case .sharp: return "♯"
        case .flat: return "♭"
        }
    }
}

enum SpellingPreference { case sharp, flat }

struct Spelling: Equatable {
    let letter: Int // 0 = C ... 6 = B
    let accidental: Accidental
    let octave: Int

    var name: String { String(Array("CDEFGAB")[letter]) + accidental.symbol }
    var diatonic: Int { octave * 7 + letter }
}

struct Spot: Hashable, Codable {
    let s: Int
    let f: Int
}

enum Theory {
    static let naturalLetter: [Int: Int] = [0: 0, 2: 1, 4: 2, 5: 3, 7: 4, 9: 5, 11: 6]
    static let pitchClassNames: [[String]] = [
        ["C"], ["C♯", "D♭"], ["D"], ["D♯", "E♭"], ["E"], ["F"],
        ["F♯", "G♭"], ["G"], ["G♯", "A♭"], ["A"], ["A♯", "B♭"], ["B"],
    ]

    static func pitchClass(_ midi: Int) -> Int { ((midi % 12) + 12) % 12 }
    static func isNatural(_ pc: Int) -> Bool { naturalLetter[pc] != nil }

    static func spell(_ midi: Int, _ pref: SpellingPreference) -> Spelling {
        let pc = pitchClass(midi)
        let octave = Int((Double(midi) / 12).rounded(.down)) - 1
        if let letter = naturalLetter[pc] {
            return Spelling(letter: letter, accidental: .natural, octave: octave)
        }
        if pref == .flat {
            return Spelling(letter: naturalLetter[pc + 1]!, accidental: .flat, octave: octave)
        }
        return Spelling(letter: naturalLetter[pc - 1]!, accidental: .sharp, octave: octave)
    }
}
