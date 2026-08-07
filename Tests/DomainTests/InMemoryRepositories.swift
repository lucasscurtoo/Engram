import Foundation
import Domain

// Minimal in-memory doubles for service tests. Tag filtering intentionally requires
// the note store so CardQuery.tag behaves like the real (note-joined) query.

actor InMemoryStore {
    var decks: [UUID: Deck] = [:]
    var notes: [UUID: Note] = [:]
    var noteTypes: [UUID: NoteType] = [:]
    var cards: [UUID: Card] = [:]
    var logs: [ReviewLog] = []

    func seed(decks: [Deck] = [], noteTypes: [NoteType] = [], notes: [Note] = [], cards: [Card] = []) {
        for deck in decks { self.decks[deck.id] = deck }
        for type in noteTypes { self.noteTypes[type.id] = type }
        for note in notes { self.notes[note.id] = note }
        for card in cards { self.cards[card.id] = card }
    }

    func setDeck(_ deck: Deck) { decks[deck.id] = deck }
    func setNote(_ note: Note) { notes[note.id] = note }
    func setCard(_ card: Card) { cards[card.id] = card }
    func appendLog(_ log: ReviewLog) { logs.append(log) }
    func removeCards(ids: [UUID]) { for id in ids { cards[id] = nil } }
    func removeNote(id: UUID) { notes[id] = nil }
    func removeDeck(id: UUID) { decks[id] = nil }

    func query(_ query: CardQuery) -> [Card] {
        var result = cards.values.filter { card in
            if let deckIDs = query.deckIDs, !deckIDs.contains(card.deckID) { return false }
            if let states = query.states, !states.contains(card.state) { return false }
            if let dueBefore = query.dueBefore, card.due > dueBefore { return false }
            if let noteID = query.noteID, card.noteID != noteID { return false }
            if let tag = query.tag, notes[card.noteID]?.tags.contains(tag) != true { return false }
            return true
        }
        result.sort { $0.due < $1.due }
        if let limit = query.limit { result = Array(result.prefix(limit)) }
        return result
    }
}

struct InMemoryDeckRepository: DeckRepository {
    let store: InMemoryStore
    func allDecks() async throws -> [Deck] { await Array(store.decks.values) }
    func deck(id: UUID) async throws -> Deck? { await store.decks[id] }
    func save(_ deck: Deck) async throws { await store.setDeck(deck) }
    func delete(id: UUID) async throws { await store.removeDeck(id: id) }
}

struct InMemoryCardRepository: CardRepository {
    let store: InMemoryStore
    func cards(matching query: CardQuery) async throws -> [Card] { await store.query(query) }
    func save(_ card: Card) async throws { await store.setCard(card) }
    func delete(ids: [UUID]) async throws { await store.removeCards(ids: ids) }
}

struct InMemoryNoteRepository: NoteRepository {
    let store: InMemoryStore
    func note(id: UUID) async throws -> Note? { await store.notes[id] }
    func notes(matching query: NoteQuery) async throws -> [Note] {
        await store.notes.values.filter { note in
            if let deckIDs = query.deckIDs, !deckIDs.contains(note.deckID) { return false }
            if let tag = query.tag, !note.tags.contains(tag) { return false }
            if let text = query.text,
               !note.fields.values.contains(where: { $0.localizedCaseInsensitiveContains(text) }) { return false }
            return true
        }
    }
    func save(_ note: Note) async throws { await store.setNote(note) }
    func delete(id: UUID) async throws { await store.removeNote(id: id) }
}

struct InMemoryNoteTypeRepository: NoteTypeRepository {
    let store: InMemoryStore
    func noteType(id: UUID) async throws -> NoteType? { await store.noteTypes[id] }
    func allNoteTypes() async throws -> [NoteType] { await Array(store.noteTypes.values) }
    func save(_ noteType: NoteType) async throws {}
}

struct InMemoryReviewLogRepository: ReviewLogRepository {
    let store: InMemoryStore
    func append(_ log: ReviewLog) async throws { await store.appendLog(log) }
    func logs(from: Date, to: Date) async throws -> [ReviewLog] {
        await store.logs.filter { $0.reviewedAt >= from && $0.reviewedAt <= to }
    }
}
