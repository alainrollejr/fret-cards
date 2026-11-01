import SwiftUI

/// One note on a five-line staff, drawn like the printed cards.
struct StaffView: View {
    let spelling: Spelling
    let instrument: Instrument
    let maxFret: Int
    var cornerLabel: String?
    var compact = false

    private let gap: CGFloat = 12
    private let bot: CGFloat = 112 // y of the bottom staff line

    var body: some View {
        let clef = instrument.clef
        let step = spelling.diatonic - clef.bottomLine // 0 = bottom line, 1 = space above it, ...
        let topStep = max(8, Theory.spell(instrument.open[0] + maxFret, .flat).diatonic - clef.bottomLine)
        let lowStep = Theory.spell(instrument.open.last!, .sharp).diatonic - clef.bottomLine
        let yTop = bot - CGFloat(topStep) * gap / 2 - 38 // room for the note name
        let yBot = bot + CGFloat(max(7, -lowStep)) * gap / 2 + 14
        let width: CGFloat = compact ? 220 : 300
        let height = yBot - yTop
        let noteX: CGFloat = compact ? 140 : 180

        Canvas { context, size in
            var ctx = context
            let k = size.width / width
            ctx.scaleBy(x: k, y: k)
            ctx.translateBy(x: 0, y: -yTop)
            let c = ctx
            let ink = GraphicsContext.Shading.color(.primary)

            func line(_ a: CGPoint, _ b: CGPoint, _ w: CGFloat) {
                var p = Path()
                p.move(to: a)
                p.addLine(to: b)
                c.stroke(p, with: ink, lineWidth: w)
            }
            func text(_ t: Text, baselineAt p: CGPoint, anchor: UnitPoint) {
                let r = c.resolve(t)
                let sz = r.measure(in: CGSize(width: 1000, height: 1000))
                let base = r.firstBaseline(in: sz)
                c.draw(r, at: CGPoint(x: p.x, y: p.y - base), anchor: anchor)
            }
            let musicFont = Font.custom(Theme.musicFont, size: gap * 4.2)

            for i in 0..<5 {
                let y = bot - CGFloat(i) * gap
                line(CGPoint(x: 6, y: y), CGPoint(x: width - 6, y: y), 1)
            }
            let clefBaseline = clef == .treble ? bot - gap : bot - 0.75 * gap
            text(Text(clef.glyph).font(musicFont).foregroundColor(.primary), baselineAt: CGPoint(x: 10, y: clefBaseline), anchor: .topLeading)

            var ledgers: [Int] = []
            if step <= -2 { ledgers += stride(from: -2, through: step, by: -2) }
            if step >= 10 { ledgers += stride(from: 10, through: step, by: 2) }
            for l in ledgers {
                let y = bot - CGFloat(l) * gap / 2
                line(CGPoint(x: noteX - 14, y: y), CGPoint(x: noteX + 14, y: y), 1.2)
            }

            let y = bot - CGFloat(step) * gap / 2
            let head = Path(ellipseIn: CGRect(x: -7.2, y: -5.2, width: 14.4, height: 10.4))
                .applying(CGAffineTransform(rotationAngle: -.pi / 9).concatenating(CGAffineTransform(translationX: noteX, y: y)))
            c.fill(head, with: ink)
            if step < 4 {
                line(CGPoint(x: noteX + 6.6, y: y - 1), CGPoint(x: noteX + 6.6, y: y - gap * 3.4), 1.4)
            } else {
                line(CGPoint(x: noteX - 6.6, y: y + 1), CGPoint(x: noteX - 6.6, y: y + gap * 3.4), 1.4)
            }
            if spelling.accidental != .natural {
                let dy: CGFloat = spelling.accidental == .flat ? 3 : 5
                text(Text(spelling.accidental.symbol).font(.custom(Theme.musicFont, size: 30)).foregroundColor(.primary),
                     baselineAt: CGPoint(x: noteX - 13, y: y + dy), anchor: .topTrailing)
            }

            let nameText = Text(spelling.name)
                .font(.system(size: compact ? 22 : 26, weight: .bold, design: .rounded))
                .foregroundColor(Theme.accent)
            c.draw(nameText, at: CGPoint(x: width - 10, y: yTop + 2), anchor: .topTrailing)

            if let label = cornerLabel, !compact {
                let bw: CGFloat = label.count > 1 ? 40 : 24
                let box = CGRect(x: width - 8 - bw, y: yBot - 30, width: bw, height: 22)
                c.stroke(Path(box), with: ink, lineWidth: 1)
                c.draw(Text(label).font(.system(size: 12, design: .serif)).foregroundColor(.primary),
                       at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
            }
        }
        .aspectRatio(width / height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("\(spelling.name) on the \(clef.name) staff")
    }
}
