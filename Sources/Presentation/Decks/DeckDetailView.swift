import Application
import Domain
import SwiftUI

/// Deck detail: header (full "Parent::Child" name, rolled-up counts, Study) on top of
/// the note browser scoped to the deck and its subdecks.
///
/// Dense screen: header sits on the content surface, separated by a hairline, and the
/// counts are monospaced because they are data.
struct DeckDetailView: View {
    let summary: DeckService.DeckSummary
    let decks: [Deck]
    /// Called after a note is added, edited or deleted so the sidebar counts refresh.
    let onNotesChanged: () async -> Void

    @Environment(StudyLauncher.self) private var launcher

    var body: some View {
        VStack(spacing: 0) {
            header
            CardListView(
                deckID: summary.deck.id, deckIDs: deckIDs, onNotesChanged: onNotesChanged
            )
        }
        .background(Theme.bg1)
    }

    private var deckIDs: [UUID] {
        // Sorted so the value is stable across renders (`CardListView` keys a task on it).
        DeckTree.subtreeIDs(of: summary.deck.id, in: decks).sorted { $0.uuidString < $1.uuidString }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.space4) {
            VStack(alignment: .leading, spacing: Theme.space1) {
                Text(DeckTree.fullName(of: summary.deck.id, in: decks))
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("^[\(summary.cardCount) cards](inflect: true) · \(summary.dueCount) due today")
                    .font(Theme.mono(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.space4)
            // Secondary on purpose: practice is the exception, Study is the habit.
            Button("Cram") { launcher.study(.deck(summary.deck.id), mode: .cram) }
                .buttonStyle(.quiet)
                .help("Practice every card without affecting the schedule")
                .accessibilityLabel("Practice this deck")
            // The one strong element on this screen.
            Button {
                launcher.study(.deck(summary.deck.id))
            } label: {
                HStack(spacing: Theme.space2) {
                    Image(systemName: "play.fill").font(.caption)
                    Text("Study")
                    KeyHint("⌘S", onAccent: true)
                }
            }
            .buttonStyle(.accentAction)
            .keyboardShortcut("s", modifiers: [.command])
            .help("Study this deck and its subdecks")
            .accessibilityLabel("Study this deck")
        }
        .padding(Theme.space4)
        .background(Theme.bg1)
        .bottomHairline()
    }
}
