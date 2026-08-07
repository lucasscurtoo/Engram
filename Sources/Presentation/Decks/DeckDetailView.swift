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
        HStack(alignment: .center, spacing: Theme.space4) {
            VStack(alignment: .leading, spacing: Theme.space1) {
                Text(DeckTree.fullName(of: summary.deck.id, in: decks))
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("\(summary.cardCount) cards · \(summary.dueCount) due today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.space4)
            // The one strong element on this screen.
            Button {
                launcher.scope = .deck(summary.deck.id)
            } label: {
                Label("Study", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut("s", modifiers: [.command])
            .help("Study this deck and its subdecks")
        }
        .padding(Theme.space4)
    }
}
