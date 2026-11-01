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
                Section("Quiz") {
                    Picker("Quiz", selection: $store.settings.mode) {
                        ForEach(QuizMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Frets") {
                    Picker("Frets", selection: $store.settings.maxFret) {
                        Text("Position I (0–4)").tag(4)
                        Text("0–5").tag(5)
                        Text("0–7").tag(7)
                        Text("0–12").tag(12)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    Toggle("Include sharps and flats", isOn: $store.settings.accidentals)
                }
                Section("Sound") {
                    Picker("Sound", selection: $store.settings.sound) {
                        ForEach(SoundMode.allCases) { Text($0.title).tag($0) }
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
}
