import Foundation
import Domain

/// Deck + note management use cases (M3 backs onto this).
public actor DeckService {
    public struct DeckSummary: Sendable, Hashable {
        public let deck: Deck
        /// Includes subdecks.
        public let cardCount: Int
        public let dueCount: Int
    }

    private let deckRepository: any DeckRepository
    private let cardRepository: any CardRepository
    private let noteRepository: any NoteRepository

    public init(
        deckRepository: any DeckRepository,
        cardRepository: any CardRepository,
        noteRepository: any NoteRepository
    ) {
        self.deckRepository = deckRepository
        self.cardRepository = cardRepository
        self.noteRepository = noteRepository
    }

    public func createDeck(
        name: String, parentID: UUID? = nil, config: DeckConfig = DeckConfig(), now: Date
    ) async throws -> Deck {
        let deck = Deck(name: name, parentID: parentID, config: config, createdAt: now)
        try await deckRepository.save(deck)
        return deck
    }

    public func renameDeck(id: UUID, to name: String) async throws {
        guard var deck = try await deckRepository.deck(id: id) else { return }
        deck.name = name
        try await deckRepository.save(deck)
    }

    public func updateConfig(deckID: UUID, config: DeckConfig) async throws {
        guard var deck = try await deckRepository.deck(id: deckID) else { return }
        deck.config = config
        try await deckRepository.save(deck)
    }

    /// Cascades subdecks/notes/cards — enforced by the repository implementation.
    public func deleteDeck(id: UUID) async throws {
        try await deckRepository.delete(id: id)
    }

    /// Creates the note AND its generated cards through the NoteType (seam 1).
    /// This is the single write path for both the editor and Quick Add.
    public func addNote(
        deckID: UUID, noteType: NoteType = .basic,
        fields: [String: String], tags: [String] = [], now: Date
    ) async throws -> Note {
        let note = Note(
            noteTypeID: noteType.id, deckID: deckID,
            fields: fields, tags: tags, createdAt: now, modifiedAt: now
        )
        try await noteRepository.save(note)
        for card in noteType.makeCards(for: note, createdAt: now) {
            try await cardRepository.save(card)
        }
        return note
    }

    public func updateNote(_ note: Note, now: Date) async throws {
        var note = note
        note.modifiedAt = now
        try await noteRepository.save(note)
        // TODO(owner): when editable NoteTypes arrive, re-sync generated cards here.
    }

    /// Sidebar data: every deck with rolled-up card/due counts (subdecks included).
    public func summaries(now: Date) async throws -> [DeckSummary] {
        let decks = try await deckRepository.allDecks()
        // ponytail: single whole-table scan, counted in memory; move to dedicated
        // count queries in the repository if this gets slow at scale.
        let cards = try await cardRepository.cards(matching: CardQuery())
        return decks.map { deck in
            let subtree = DeckTree.subtreeIDs(of: deck.id, in: decks)
            let mine = cards.filter { subtree.contains($0.deckID) }
            return DeckSummary(
                deck: deck,
                cardCount: mine.count,
                dueCount: mine.filter { $0.state != .new && $0.due <= now }.count
            )
        }
    }
}
