import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: QuizStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Instrument") {
                    Picker("Instrument", selection: $store.settings.instrument) {
                        ForEach(Instrument.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Picker("Quiz", selection: $store.settings.mode) {
                        ForEach(QuizMode.allCases.filter { store.settings.instrument == .guitar || !$0.isChord }) {
                            Text($0.title).tag($0)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Quiz")
                } footer: {
                    if store.settings.instrument != .guitar { Text("Chord quizzes are for guitar.") }
                }
                Section {
                    Stepper("Lowest fret: \(store.settings.minFret)", value: $store.settings.minFret,
                            in: 0...(store.settings.maxFret - Settings.minSpan))
                    Stepper("Highest fret: \(store.settings.maxFret)", value: $store.settings.maxFret,
                            in: (store.settings.minFret + Settings.minSpan)...Settings.fretLimit)
                    HStack {
                        presetButton("Whole neck", 0...12)
                        presetButton("Position I", 0...4)
                        presetButton("Position V", 5...8)
                    }
                    Toggle("Include sharps and flats", isOn: $store.settings.accidentals)
                } header: {
                    Text("Frets")
                } footer: {
                    Text("Quizzes use only frets \(store.settings.rangeText). Open strings count when the lowest fret is 0.")
                }
                Section {
                    Picker("Fretboard", selection: $store.settings.layout) {
                        ForEach(FretLayout.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Fretboard")
                } footer: {
                    Text("Horizontal: high e on top, scrolls sideways if it doesn't fit (turn the phone for the whole neck). Vertical: low E on the left, nut at the top.")
                }
                Section("Sound") {
                    Picker("Sound", selection: $store.settings.sound) {
                        ForEach(SoundMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Chord sound") {
                    Picker("Chord sound", selection: $store.settings.chordPlay) {
                        ForEach(ChordPlayStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Needs practice") {
                    if store.weakList.isEmpty {
                        Text("Notes you miss will show up here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.weakList, id: \.self) { Text($0) }
                    }
                }
                Section {
                    Button("Reset score and progress", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset your score and the list of notes that need practice?",
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { store.resetProgress() }
            }
        }
    }

    private func presetButton(_ title: String, _ frets: ClosedRange<Int>) -> some View {
        Button(title) {
            var st = store.settings
            st.minFret = frets.lowerBound
            st.maxFret = frets.upperBound
            store.settings = st
        }
        .buttonStyle(.bordered)
        .font(.footnote)
        .tint(store.settings.frets == frets ? Theme.accent : .secondary)
        .frame(maxWidth: .infinity)
    }
}
