import SwiftUI

@main
struct FretCardsApp: App {
    @StateObject private var store = QuizStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(Theme.accent)
        }
    }
}
