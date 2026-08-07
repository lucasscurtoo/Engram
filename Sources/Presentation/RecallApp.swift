import SwiftUI

enum AppInfo {
    /// Working title — rename here (and in project.yml), nowhere else.
    static let name = "Recall"
}

@main
struct RecallApp: App {
    var body: some Scene {
        WindowGroup(AppInfo.name) {
            ContentView()
        }
        // TODO(owner): M3 — Quick Add window + global keyboard shortcut.
        // TODO(owner): M5 — MenuBarExtra focus timer (MenuBarTimer.swift).
    }
}

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            DeckListView()
        } detail: {
            Text("Select a deck to get started")
                .foregroundStyle(.secondary)
        }
    }
}
