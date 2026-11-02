import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: QuizStore
    @State private var showSettings = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Phone turned sideways: everything has to fit in one short screen.
    private var landscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        NavigationStack {
            Group {
                if landscape { landscapeBody } else { portraitBody }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(landscape ? .hidden : .visible, for: .navigationBar)
            .navigationTitle("Fret Cards")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { settingsButton }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(store)
            }
        }
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Settings")
    }

    // MARK: - Landscape: a slim strip with the question, then the neck across the full width

    private var landscapeBody: some View {
        let card = store.card
        return ScrollView {
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    compactPrompt
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.promptTitle)
                            .font(.headline)
                            .lineLimit(2)
                        feedbackText(compact: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("\(store.stats.right)/\(store.stats.total) · \(Image(systemName: "flame")) \(store.stats.streak)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if store.settings.sound != .off {
                                Button { store.playCurrent() } label: { Image(systemName: "play.fill") }
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.circle)
                                    .accessibilityLabel("Play")
                            }
                            settingsButton
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.circle)
                        }
                        nextButton(compact: true)
                    }
                }
                .frame(minHeight: 84)

                switch card.type {
                case .fret:
                    board(marks: store.promptMarks)
                    noteGrid(columns: store.settings.accidentals ? 12 : 7, height: 40)
                case .chordName:
                    board(chord: card.chord?.voicing, chordKind: store.chordKind)
                    chordGrid(columns: 7, height: 38)
                default:
                    tapBoard
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    /// Small card left of the question: the note on the staff, or the name to find.
    @ViewBuilder
    private var compactPrompt: some View {
        let card = store.card
        let staff = card.type == .staff || (card.type == .fret && card.result != nil)
        if staff || card.type == .all || card.type == .same || card.type == .chordShape {
            Group {
                if staff {
                    StaffView(spelling: card.spelling, instrument: store.settings.instrument,
                              maxFret: store.settings.maxFret, compact: true)
                } else {
                    Text(card.chord?.name ?? card.spelling.name)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5)
                }
            }
            .frame(width: 170, height: 76)
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary, lineWidth: 1.5))
        }
    }

    private func board(marks: [FretMark] = [], chord: Voicing? = nil, chordKind: FretMark.Kind = .question) -> some View {
        FretboardView(instrument: store.settings.instrument, frets: store.card.frets, layout: store.settings.fretLayout,
                      marks: marks, chord: chord, chordKind: chordKind, compact: landscape)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Portrait

    private var portraitBody: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statsRow
                    HStack(alignment: .center, spacing: 12) {
                        Text(store.promptTitle)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if store.settings.sound != .off {
                            Button {
                                store.playCurrent()
                            } label: {
                                Label("Play", systemImage: "play.fill")
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                        }
                    }
                    promptCard
                    answerArea
                    if store.card.type == .fret, store.card.result != nil {
                        StaffView(spelling: store.card.spelling, instrument: store.settings.instrument,
                                  maxFret: store.settings.maxFret, compact: true)
                            .frame(maxWidth: 260)
                            .frame(maxWidth: .infinity)
                    }
                    feedbackRow
                }
                .padding()
            }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            Label("\(store.stats.right) / \(store.stats.total)", systemImage: "checkmark.circle")
            Label("\(store.stats.streak)", systemImage: "flame")
            Text("Best \(store.stats.best)")
            Spacer()
            Text(store.settings.instrument.title)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var promptCard: some View {
        let card = store.card
        Group {
            switch card.type {
            case .staff:
                StaffView(spelling: card.spelling, instrument: store.settings.instrument,
                          maxFret: store.settings.maxFret, cornerLabel: store.cornerLabel)
                    .frame(maxHeight: 130) // keep the note small so the neck gets the room
            case .fret:
                FretboardView(instrument: store.settings.instrument, frets: card.frets, layout: store.settings.fretLayout, marks: store.promptMarks)
            case .chordName:
                FretboardView(instrument: store.settings.instrument, frets: card.frets, layout: store.settings.fretLayout,
                              chord: card.chord?.voicing, chordKind: store.chordKind)
            case .all, .same, .chordShape:
                VStack(spacing: 6) {
                    Text(card.chord?.name ?? card.spelling.name)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                    Text(store.promptSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary, lineWidth: 1.5))
    }

    @ViewBuilder
    private var answerArea: some View {
        let card = store.card
        if card.type == .fret {
            noteGrid()
        } else if card.type == .chordName {
            chordGrid()
        } else {
            tapBoard
        }
    }

    /// The neck you answer on.
    private var tapBoard: some View {
        let card = store.card
        return FretboardView(instrument: store.settings.instrument, frets: card.frets, layout: store.settings.fretLayout,
                             marks: store.answerMarks, chord: card.result?.voicing, showFingers: false, compact: landscape,
                             onTap: card.result == nil ? { store.tap($0) } : nil)
            .padding(.vertical, landscape ? 2 : 4)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    private func noteGrid(columns: Int = 4, height: CGFloat = 52) -> some View {
        let card = store.card
        let pcs = (0..<12).filter { store.settings.accidentals || Theory.isNatural($0) }
        let target = Theory.pitchClass(card.midi)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(pcs, id: \.self) { pc in
                let names = Theory.pitchClassNames[pc]
                let state: Tone = {
                    guard let r = card.result else { return .neutral }
                    if pc == target { return .good }
                    return r.pickedPC == pc ? .bad : .neutral
                }()
                Button {
                    store.pick(pitchClass: pc)
                } label: {
                    VStack(spacing: 0) {
                        Text(names[0]).font(.title3.weight(.bold))
                        if names.count > 1 {
                            Text(names[1]).font(.caption.weight(.semibold)).opacity(0.7)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: height)
                    .foregroundStyle(state == .neutral ? Color.primary : .white)
                    .background(RoundedRectangle(cornerRadius: 10).fill(fill(for: state)))
                }
                .buttonStyle(.plain)
                .disabled(card.result != nil)
            }
        }
    }

    private func chordGrid(columns: Int = 4, height: CGFloat = 50) -> some View {
        let card = store.card
        let keys = Chords.keys(minFret: store.settings.minFret, maxFret: store.settings.maxFret, accidentals: store.settings.accidentals)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(keys, id: \.self) { key in
                let state: Tone = {
                    guard let r = card.result else { return .neutral }
                    if key == card.chord?.key { return .good }
                    return r.pickedChord == key ? .bad : .neutral
                }()
                Button {
                    store.pick(chord: key)
                } label: {
                    Text(Chords.parse(key[...]).map { Chords.name($0.pc, $0.quality) } ?? key)
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: height)
                        .foregroundStyle(state == .neutral ? Color.primary : .white)
                        .background(RoundedRectangle(cornerRadius: 10).fill(fill(for: state)))
                }
                .buttonStyle(.plain)
                .disabled(card.result != nil)
            }
        }
    }

    private func fill(for tone: Tone) -> Color {
        switch tone {
        case .neutral: return Color(.secondarySystemGroupedBackground)
        case .good: return Theme.good
        case .bad: return Theme.bad
        }
    }

    private var feedbackRow: some View {
        HStack(alignment: .center, spacing: 12) {
            feedbackText(compact: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            nextButton(compact: false)
        }
        .frame(minHeight: 52)
    }

    @ViewBuilder
    private func feedbackText(compact: Bool) -> some View {
        let fb = store.feedback
        // Sideways there is no room for the prompt's subtitle, so it stands in until there is feedback.
        let hint = compact && fb.main.isEmpty && store.card.type != .staff && store.card.type != .fret && store.card.type != .chordName
            ? store.promptSubtitle : fb.hint
        VStack(alignment: .leading, spacing: 2) {
            if !fb.main.isEmpty {
                Text(fb.main)
                    .font((compact ? Font.subheadline : .body).weight(fb.tone == .good ? .bold : .regular))
                    .foregroundStyle(fb.tone == .good ? Theme.good : fb.tone == .bad ? Theme.bad : .primary)
            }
            if !hint.isEmpty {
                Text(hint).font(compact ? .caption : .subheadline).foregroundStyle(.secondary)
            }
        }
        .lineLimit(compact ? 3 : nil)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func nextButton(compact: Bool) -> some View {
        let answered = store.card.result != nil || store.nextTitle == "Check"
        Group {
            if answered {
                Button(store.nextTitle) { store.next() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button(store.nextTitle) { store.next() }
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(compact ? .regular : .large)
        .animation(.default, value: answered)
    }
}
