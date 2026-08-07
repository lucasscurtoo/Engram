import Application
import Domain
import SwiftUI

/// Sidebar: hierarchical deck tree with rolled-up counts, plus the fixed
/// Stats/Focus entries (placeholders until M5/M6).
struct DeckListView: View {
    let model: DeckListViewModel
    @Binding var selection: AppRoute?

    @State private var sheet: DeckSheet?
    @State private var deckPendingDeletion: Deck?

    var body: some View {
        List(selection: $selection) {
            Section("Decks") {
                if model.tree.isEmpty {
                    Text(model.isLoading ? "Loading…" : "No decks yet — create one")
                        .foregroundStyle(.secondary)
                } else {
                    OutlineGroup(model.tree, children: \.children) { node in
                        DeckRow(summary: node.summary)
                            .tag(AppRoute.deck(node.id))
                            .contextMenu { menu(for: node.summary.deck) }
                    }
                }
            }
            Section {
                Label("Stats", systemImage: "chart.bar").tag(AppRoute.stats)
                Label("Focus", systemImage: "timer").tag(AppRoute.focus)
            }
        }
        .navigationTitle(AppInfo.name)
        .toolbar {
            Button {
                sheet = .add(parentID: nil)
            } label: {
                Label("New Deck", systemImage: "plus")
            }
            .help("New deck")
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add(let parentID):
                DeckFormSheet(
                    title: "New Deck", decks: model.decks, name: "", parentID: parentID,
                    showsParentPicker: true
                ) { name, parentID in
                    await model.createDeck(name: name, parentID: parentID)
                }
            case .rename(let deck):
                DeckFormSheet(
                    title: "Rename Deck", decks: model.decks, name: deck.name,
                    parentID: deck.parentID, showsParentPicker: false
                ) { name, _ in
                    await model.rename(deckID: deck.id, to: name)
                }
            case .configure(let deck):
                DeckConfigSheet(deckName: model.fullName(of: deck.id), config: deck.config) { config in
                    await model.updateConfig(deckID: deck.id, config: config)
                }
            }
        }
        .confirmationDialog(
            deckPendingDeletion.map { "Delete “\($0.name)”?" } ?? "",
            isPresented: Binding(
                get: { deckPendingDeletion != nil },
                set: { if !$0 { deckPendingDeletion = nil } }
            ),
            presenting: deckPendingDeletion
        ) { deck in
            Button("Delete Deck", role: .destructive) {
                Task {
                    if selection == .deck(deck.id) { selection = nil }
                    await model.delete(deckID: deck.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its subdecks, notes and cards are deleted too. This cannot be undone.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func menu(for deck: Deck) -> some View {
        Button("Rename…") { sheet = .rename(deck) }
        Button("Add Subdeck…") { sheet = .add(parentID: deck.id) }
        Button("Configure…") { sheet = .configure(deck) }
        Divider()
        Button("Delete…", role: .destructive) { deckPendingDeletion = deck }
    }
}

private enum DeckSheet: Identifiable {
    case add(parentID: UUID?)
    case rename(Deck)
    case configure(Deck)

    var id: String {
        switch self {
        case .add(let parentID): "add-\(parentID?.uuidString ?? "root")"
        case .rename(let deck): "rename-\(deck.id)"
        case .configure(let deck): "configure-\(deck.id)"
        }
    }
}

private struct DeckRow: View {
    let summary: DeckService.DeckSummary

    var body: some View {
        HStack {
            Label(summary.deck.name, systemImage: "rectangle.stack")
            Spacer()
            if summary.dueCount > 0 {
                Text("\(summary.dueCount)")
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                    .help("Due today")
            }
            Text("\(summary.cardCount)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("Cards, subdecks included")
        }
    }
}
