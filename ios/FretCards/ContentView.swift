import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: QuizStore
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
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
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Fret Cards")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(store)
            }
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
            noteGrid
        } else if card.type == .chordName {
            chordGrid
        } else {
            FretboardView(instrument: store.settings.instrument, frets: card.frets, layout: store.settings.fretLayout, marks: store.answerMarks,
                          chord: card.result?.voicing, showFingers: false,
                          onTap: card.result == nil ? { store.tap($0) } : nil)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    private var noteGrid: some View {
        let card = store.card
        let pcs = (0..<12).filter { store.settings.accidentals || Theory.isNatural($0) }
        let target = Theory.pitchClass(card.midi)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
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
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(state == .neutral ? Color.primary : .white)
                    .background(RoundedRectangle(cornerRadius: 10).fill(fill(for: state)))
                }
                .buttonStyle(.plain)
                .disabled(card.result != nil)
            }
        }
    }

    private var chordGrid: some View {
        let card = store.card
        let keys = Chords.keys(minFret: store.settings.minFret, maxFret: store.settings.maxFret, accidentals: store.settings.accidentals)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
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
                        .frame(maxWidth: .infinity, minHeight: 50)
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
        let fb = store.feedback
        let answered = store.card.result != nil || store.nextTitle == "Check"
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if !fb.main.isEmpty {
                    Text(fb.main)
                        .font(.body.weight(fb.tone == .good ? .bold : .regular))
                        .foregroundStyle(fb.tone == .good ? Theme.good : fb.tone == .bad ? Theme.bad : .primary)
                }
                if !fb.hint.isEmpty {
                    Text(fb.hint).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            if answered {
                Button(store.nextTitle) { store.next() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Button(store.nextTitle) { store.next() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .frame(minHeight: 52)
        .animation(.default, value: answered)
    }
}
