import SwiftUI

/// Sidebar: deck tree + fixed entries. TODO(owner): M3 — real data via DeckListViewModel
/// (DeckService.summaries), subdeck disclosure, add/rename/delete, per-deck config.
struct DeckListView: View {
    var body: some View {
        List {
            Section("Decks") {
                Text("No decks yet")
                    .foregroundStyle(.secondary)
            }
            Section {
                Label("Stats", systemImage: "chart.bar")
                Label("Focus", systemImage: "timer")
            }
        }
        .navigationTitle(AppInfo.name)
    }
}
