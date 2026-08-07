import Application
import Domain
import SwiftUI

/// Deck detail: header (full "Parent::Child" name, rolled-up counts, Study placeholder)
/// on top of the note browser scoped to the deck and its subdecks.
struct DeckDetailView: View {
    let summary: DeckService.DeckSummary
    let decks: [Deck]
    /// Called after a note is added, edited or deleted so the sidebar counts refresh.
    let onNotesChanged: () async -> Void

    @Environment(StudyLauncher.self) private var launcher

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            CardListView(
                deckID: summary.deck.id, deckIDs: deckIDs, onNotesChanged: onNotesChanged
            )
        }
    }

    private var deckIDs: [UUID] {
        // Sorted so the value is stable across renders (`CardListView` keys a task on it).
        DeckTree.subtreeIDs(of: summary.deck.id, in: decks).sorted { $0.uuidString < $1.uuidString }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(DeckTree.fullName(of: summary.deck.id, in: decks))
                    .font(.title2)
                Text("\(summary.cardCount) cards · \(summary.dueCount) due today")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Study") { launcher.scope = .deck(summary.deck.id) }
                .keyboardShortcut("s", modifiers: [.command])
                .help("Study this deck and its subdecks")
        }
        .padding()
    }
}
