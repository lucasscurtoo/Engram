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

    @Environment(StudyLauncher.self) private var launcher

    var body: some View {
        List(selection: $selection) {
            Section {
                if model.tree.isEmpty {
                    Text(model.isLoading ? "Loading…" : "No decks yet")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, Theme.space1)
                } else {
                    OutlineGroup(model.tree, children: \.children) { node in
                        DeckRow(summary: node.summary)
                            .tag(AppRoute.deck(node.id))
                            .contextMenu { menu(for: node.summary.deck) }
                    }
                }
            }
            Section {
                SidebarRow(title: "Stats", symbol: "chart.bar.xaxis").tag(AppRoute.stats)
                SidebarRow(title: "Focus", symbol: "timer").tag(AppRoute.focus)
            }
        }
        .navigationTitle(AppInfo.name)
        // Things' "+ New List": always reachable, never in the way.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                sheet = .add(parentID: nil)
            } label: {
                Label("New Deck", systemImage: "plus")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.space3)
            .padding(.vertical, Theme.space2)
        }
        .toolbar {
            Button {
                launcher.scope = .all
            } label: {
                Label("Study All", systemImage: "play.fill")
            }
            .help("Study every deck")
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

/// Sidebar entry with the app's quiet icon treatment. Used by the fixed rows;
/// `DeckRow` mirrors its metrics so every row in the list lines up.
private struct SidebarRow: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: Theme.space2) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
        }
        .padding(.vertical, Theme.space1)
    }
}

private struct DeckRow: View {
    let summary: DeckService.DeckSummary

    var body: some View {
        HStack(spacing: Theme.space2) {
            Image(systemName: "rectangle.stack")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(summary.deck.name)
                .lineLimit(1)
            Spacer(minLength: Theme.space2)
            dueBadge
        }
        .padding(.vertical, Theme.space1)
    }

    /// Accent capsule while something is due, a quiet nothing once the deck is clear.
    @ViewBuilder
    private var dueBadge: some View {
        if summary.dueCount > 0 {
            Text("\(summary.dueCount)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.space2)
                .padding(.vertical, Theme.space1 / 2)
                .background(Theme.accent, in: .capsule)
                .help("Due today")
        }
    }
}
