import SwiftUI

enum FretLayout: String, CaseIterable, Codable, Identifiable {
    case auto, horizontal, vertical
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto"
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }
}

struct FretMark {
    enum Kind { case question, good, bad, missed }
    let spot: Spot
    let kind: Kind
    let label: String
    var round = false // finger-number dot on a chord diagram
    var root = false // the chord's root note, always in its own colour
}

/// Fretboard in tab orientation. Horizontal: highest string on top, nut on the left.
/// Vertical: low E on the left, nut at the top. Open strings sit before the nut,
/// and the board shows only the frets in `frets`.
struct FretboardView: View {
    let instrument: Instrument
    let frets: ClosedRange<Int>
    var layout = FretLayout.auto
    var marks: [FretMark] = []
    var chord: Voicing?
    var chordKind: FretMark.Kind = .question
    var showFingers = true
    var onTap: ((Spot) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var available: CGFloat = 340

    /// Positions along the neck are `u`, across the strings `v`; `point` maps them to the screen.
    private struct Geometry {
        let n: Int
        let frets: ClosedRange<Int>
        let layout: FretLayout
        let available: CGFloat

        var vertical: Bool { layout == .vertical }
        var hasOpen: Bool { frets.lowerBound == 0 }
        var lo: Int { max(1, frets.lowerBound) }
        var cells: Int { frets.upperBound - lo + 1 }

        var uLabel: CGFloat { vertical ? 10 : 8 }
        var uStrings: CGFloat { vertical ? 22 : 16 }
        var u0: CGFloat { vertical ? (hasOpen ? 62 : 30) : (hasOpen ? 56 : 24) } // nut or first fret wire
        var fw: CGFloat {
            vertical ? 46 : max(40, (available - u0 - 8) / CGFloat(cells))
        }
        var uEnd: CGFloat { u0 + CGFloat(cells) * fw }

        var sp: CGFloat { vertical ? min(64, (available - 32) / CGFloat(n)) : 31 }
        var vLeft: CGFloat { 26 + (available - 32 - CGFloat(n) * sp) / 2 }
        func v(_ s: Int) -> CGFloat {
            vertical ? vLeft + (CGFloat(n - 1 - s) + 0.5) * sp : 34 + CGFloat(s) * sp
        }
        var vNumbers: CGFloat { vertical ? vLeft - 13 : 14 }

        var size: CGSize {
            vertical
                ? CGSize(width: available, height: uEnd + 10)
                : CGSize(width: uEnd + 8, height: v(n - 1) + 22)
        }

        func cu(_ f: Int) -> CGFloat {
            f == 0 ? (uStrings + u0) / 2 - 1 : u0 + (CGFloat(f - lo) + 0.5) * fw
        }
        func point(_ u: CGFloat, _ v: CGFloat) -> CGPoint { vertical ? CGPoint(x: v, y: u) : CGPoint(x: u, y: v) }
        func rect(u: ClosedRange<CGFloat>, v: ClosedRange<CGFloat>) -> CGRect {
            let a = point(u.lowerBound, v.lowerBound), b = point(u.upperBound, v.upperBound)
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        }
        /// Size of a note pill: as wide as a fret cell or string gap allows.
        func pillSize(_ m: FretMark) -> CGSize {
            if m.round { return CGSize(width: 24, height: 24) }
            if vertical { return CGSize(width: min(44, sp - 6), height: 22) }
            return CGSize(width: m.spot.f == 0 ? 32 : min(44, fw - 5), height: 22)
        }

        func spot(at p: CGPoint) -> Spot? {
            let u = vertical ? p.y : p.x, vv = vertical ? p.x : p.y
            guard let s = (0..<n).min(by: { abs(v($0) - vv) < abs(v($1) - vv) }), abs(v(s) - vv) <= sp / 2,
                  u <= uEnd + 6 else { return nil }
            if hasOpen, u < u0 - 2 { return u > uStrings - 12 ? Spot(s: s, f: 0) : nil }
            let i = min(cells - 1, max(0, Int(((u - u0) / fw).rounded(.down))))
            return Spot(s: s, f: lo + i)
        }
    }

    var body: some View {
        // Auto: horizontal when every fret fits across the screen (landscape), otherwise vertical.
        let wide = Geometry(n: instrument.open.count, frets: frets, layout: .horizontal, available: available)
        let fits = wide.size.width <= available + 0.5
        let g = layout == .vertical || (layout == .auto && !fits)
            ? Geometry(n: instrument.open.count, frets: frets, layout: .vertical, available: available)
            : wide
        Group {
            if !g.vertical && g.size.width > available + 0.5 {
                ScrollView(.horizontal) { board(g) }
            } else {
                board(g)
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = max(200, $0) }
        .accessibilityElement()
        .accessibilityLabel("\(instrument.title) fretboard, frets \(frets.lowerBound) to \(frets.upperBound)")
    }

    private func board(_ g: Geometry) -> some View {
        let paper: Color = colorScheme == .dark ? Color(red: 0.10, green: 0.12, blue: 0.145) : .white

        return Canvas { c, _ in
            let ink = GraphicsContext.Shading.color(.primary)
            let last = g.n - 1
            let vMin = min(g.v(0), g.v(last)), vMax = max(g.v(0), g.v(last))

            func line(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat) {
                var p = Path()
                p.move(to: a)
                p.addLine(to: b)
                c.stroke(p, with: ink, lineWidth: w)
            }

            // Inlay dots
            let mid = (vMin + vMax) / 2
            let r = min(5, g.fw / 6)
            func dot(_ f: Int, _ v: CGFloat) {
                let p = g.point(g.cu(f), v)
                c.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.inlay))
            }
            for f in [3, 5, 7, 9, 15] where f >= g.lo && f <= frets.upperBound { dot(f, mid) }
            if (g.lo...frets.upperBound).contains(12) { dot(12, mid - g.sp); dot(12, mid + g.sp) }

            // Fret numbers, frets, nut, strings
            let numberSize: CGFloat = g.fw < 50 ? 11 : 13
            for f in g.lo...frets.upperBound {
                c.draw(Text("\(f)").font(.system(size: numberSize)).foregroundColor(.secondary),
                       at: g.point(g.cu(f), g.vNumbers), anchor: .center)
            }
            for i in 0...g.cells {
                let u = g.u0 + CGFloat(i) * g.fw
                if i == 0 && g.hasOpen {
                    c.fill(Path(g.rect(u: (u - 5)...u, v: (vMin - 7)...(vMax + 7))), with: ink)
                } else {
                    line(g.point(u, vMin - 6), g.point(u, vMax + 6), 1.4)
                }
            }
            for s in 0..<g.n {
                line(g.point(g.uStrings, g.v(s)), g.point(g.uEnd, g.v(s)), instrument.stringWidths[s])
                c.draw(Text(instrument.tabNames[s]).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary),
                       at: g.point(g.uLabel, g.v(s)), anchor: .center)
            }

            func pill(_ rect: CGRect, radius: CGFloat, kind: FretMark.Kind, label: String, size: CGFloat, root: Bool = false) {
                let pill = Path(roundedRect: rect, cornerRadius: radius)
                let textColor: Color
                switch kind {
                case .missed:
                    let color = root ? Theme.root : Theme.good
                    c.fill(pill, with: .color(paper))
                    c.stroke(pill, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    textColor = color
                case _ where root:
                    c.fill(pill, with: .color(Theme.root))
                    textColor = .white
                case .question:
                    c.fill(pill, with: ink)
                    textColor = paper
                case .good:
                    c.fill(pill, with: .color(Theme.good))
                    textColor = .white
                case .bad:
                    c.fill(pill, with: .color(Theme.bad))
                    textColor = .white
                }
                c.draw(Text(label).font(.system(size: size, weight: .bold)).foregroundColor(textColor),
                       at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }

            // Chord shape: open/muted signs before the nut, a barre, finger numbers, roots in their own colour
            var allMarks = marks
            if let chord {
                for s in 0..<g.n where g.hasOpen {
                    let p = g.point(g.cu(0), g.v(s))
                    if chord.frets[s] == 0 {
                        let ring = Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
                        c.fill(ring, with: .color(paper))
                        c.stroke(ring, with: ink, lineWidth: 1.6)
                    } else if chord.frets[s] == nil {
                        c.fill(Path(CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)), with: .color(paper))
                        line(CGPoint(x: p.x - 5, y: p.y - 5), CGPoint(x: p.x + 5, y: p.y + 5), 1.8)
                        line(CGPoint(x: p.x + 5, y: p.y - 5), CGPoint(x: p.x - 5, y: p.y + 5), 1.8)
                    }
                }
                if showFingers {
                    let roots = chord.roots(open: instrument.open)
                    if let b = chord.barre {
                        let a = g.v(b.s1), z = g.v(b.s2)
                        let rect = g.rect(u: (g.cu(b.f) - 12)...(g.cu(b.f) + 12), v: (min(a, z) - 12)...(max(a, z) + 12))
                        pill(rect, radius: 12, kind: chordKind, label: "1", size: 13)
                    }
                    for (s, f) in chord.frets.enumerated() {
                        guard let f, f > 0 else { continue }
                        let spot = Spot(s: s, f: f)
                        let onBarre = chord.barre.map { f == $0.f && ($0.s1...$0.s2).contains(s) } ?? false
                        if onBarre && !roots.contains(spot) { continue }
                        allMarks.append(FretMark(spot: spot, kind: chordKind, label: "\(chord.fingers[s])",
                                                 round: true, root: roots.contains(spot)))
                    }
                }
            }

            // Note pills, styled like the printed cards
            for m in allMarks {
                let sz = g.pillSize(m)
                let p = g.point(g.cu(m.spot.f), g.v(m.spot.s))
                let rect = CGRect(x: p.x - sz.width / 2, y: p.y - sz.height / 2, width: sz.width, height: sz.height)
                let size: CGFloat = m.round ? 13 : m.label.count > 1 && sz.width < 30 ? 9.5 : 12.5
                pill(rect, radius: m.round ? 12 : 7, kind: m.kind, label: m.label, size: size, root: m.root)
            }
        }
        .frame(width: g.size.width, height: g.size.height)
        .overlay {
            if let onTap {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        if let spot = g.spot(at: value.location) { onTap(spot) }
                    })
            }
        }
    }
}
