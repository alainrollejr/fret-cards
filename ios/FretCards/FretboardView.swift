import SwiftUI

struct FretMark {
    enum Kind { case question, good, bad, missed }
    let spot: Spot
    let kind: Kind
    let label: String
}

/// Horizontal fretboard like the printed cards: top line is the highest string,
/// nut on the left, open strings left of the nut.
struct FretboardView: View {
    let instrument: Instrument
    let maxFret: Int
    var marks: [FretMark] = []
    var onTap: ((Spot) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    private struct Geometry {
        let n: Int
        let maxFret: Int
        let width: CGFloat = 340
        let xs: CGFloat = 16 // strings start here; tab labels sit left of it
        let x0: CGFloat = 56 // nut
        let x1: CGFloat = 332
        let y0: CGFloat = 34
        let sp: CGFloat = 31
        var fw: CGFloat { (x1 - x0) / CGFloat(maxFret) }
        var height: CGFloat { y0 + CGFloat(n - 1) * sp + 22 }
        func cx(_ f: Int) -> CGFloat { f == 0 ? (xs + x0) / 2 - 1 : x0 + (CGFloat(f) - 0.5) * fw }
        func sy(_ s: Int) -> CGFloat { y0 + CGFloat(s) * sp }

        func spot(at p: CGPoint) -> Spot? {
            let s = Int(((p.y - y0) / sp).rounded())
            guard s >= 0, s < n, abs(p.y - sy(s)) <= sp / 2, p.x <= x1 + 6 else { return nil }
            if p.x < x0 - 2 { return Spot(s: s, f: 0) }
            let f = min(maxFret, max(1, Int(((p.x - x0) / fw).rounded(.up))))
            return Spot(s: s, f: f)
        }
    }

    var body: some View {
        let g = Geometry(n: instrument.open.count, maxFret: maxFret)
        let paper: Color = colorScheme == .dark ? Color(red: 0.10, green: 0.12, blue: 0.145) : .white

        Canvas { context, size in
            var ctx = context
            let k = size.width / g.width
            ctx.scaleBy(x: k, y: k)
            let c = ctx
            let ink = GraphicsContext.Shading.color(.primary)
            let last = g.n - 1

            func line(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat) {
                var p = Path()
                p.move(to: a)
                p.addLine(to: b)
                c.stroke(p, with: ink, lineWidth: w)
            }

            // Inlay dots
            let mid = g.sy(0) + CGFloat(last) * g.sp / 2
            let r = min(5, g.fw / 6)
            func dot(_ f: Int, _ y: CGFloat) {
                c.fill(Path(ellipseIn: CGRect(x: g.cx(f) - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.inlay))
            }
            for f in [3, 5, 7, 9] where f <= maxFret { dot(f, mid) }
            if maxFret >= 12 { dot(12, mid - g.sp); dot(12, mid + g.sp) }

            // Fret numbers, frets, nut, strings
            let numberSize: CGFloat = maxFret > 7 ? 10 : 13
            for f in 1...maxFret {
                c.draw(Text("\(f)").font(.system(size: numberSize)).foregroundColor(.secondary),
                       at: CGPoint(x: g.cx(f), y: 14), anchor: .center)
                let x = g.x0 + CGFloat(f) * g.fw
                line(CGPoint(x: x, y: g.sy(0) - 6), CGPoint(x: x, y: g.sy(last) + 6), 1.4)
            }
            c.fill(Path(CGRect(x: g.x0 - 5, y: g.sy(0) - 7, width: 5, height: CGFloat(last) * g.sp + 14)), with: ink)
            for s in 0..<g.n {
                line(CGPoint(x: g.xs, y: g.sy(s)), CGPoint(x: g.x1, y: g.sy(s)), instrument.stringWidths[s])
                c.draw(Text(instrument.tabNames[s]).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary),
                       at: CGPoint(x: g.xs / 2, y: g.sy(s)), anchor: .center)
            }

            // Note pills, styled like the printed cards
            for m in marks {
                let w: CGFloat = m.spot.f == 0 ? 32 : min(44, g.fw - 5)
                let rect = CGRect(x: g.cx(m.spot.f) - w / 2, y: g.sy(m.spot.s) - 11, width: w, height: 22)
                let pill = Path(roundedRect: rect, cornerRadius: 7)
                let textColor: Color
                switch m.kind {
                case .question:
                    c.fill(pill, with: ink)
                    textColor = paper
                case .good:
                    c.fill(pill, with: .color(Theme.good))
                    textColor = .white
                case .bad:
                    c.fill(pill, with: .color(Theme.bad))
                    textColor = .white
                case .missed:
                    c.fill(pill, with: .color(paper))
                    c.stroke(pill, with: .color(Theme.good), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    textColor = Theme.good
                }
                let size: CGFloat = m.label.count > 1 && w < 30 ? 9.5 : 12.5
                c.draw(Text(m.label).font(.system(size: size, weight: .bold)).foregroundColor(textColor),
                       at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }
        }
        .aspectRatio(g.width / g.height, contentMode: .fit)
        .overlay {
            if let onTap {
                GeometryReader { proxy in
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { value in
                            let k = proxy.size.width / g.width
                            let p = CGPoint(x: value.location.x / k, y: value.location.y / k)
                            if let spot = g.spot(at: p) { onTap(spot) }
                        })
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(instrument.title) fretboard, frets 0 to \(maxFret)")
    }
}
