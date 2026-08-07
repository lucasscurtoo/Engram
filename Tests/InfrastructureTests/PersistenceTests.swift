import Domain
import Foundation
import SwiftData
import Testing

@testable import Infrastructure

/// A throwaway on-disk store. The container is scoped so a test can drop it and
/// reopen the same files — that reopen is the whole point of M2.
private struct TempStore: ~Copyable {
    let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EngramTests-\(UUID().uuidString)", isDirectory: true)
    }

    func open() throws -> ModelContainer { try .engram(directory: directory) }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

private func makeDeck(name: String, parentID: UUID? = nil) -> Deck {
    Deck(name: name, parentID: parentID, config: DeckConfig(requestRetention: 0.87), createdAt: epoch)
}

private func makeNote(deckID: UUID, front: String, tags: [String] = []) -> Note {
    Note(
        noteTypeID: NoteType.basic.id, deckID: deckID,
        fields: ["front": front, "back": "back of \(front)"], tags: tags,
        createdAt: epoch, modifiedAt: epoch
    )
}

// MARK: - Round trip across a container reopen

@Test func persistsAcrossContainerReopen() async throws {
    let store = TempStore()

    let deck = makeDeck(name: "Spanish")
    let subdeck = makeDeck(name: "Verbs", parentID: deck.id)
    let note = makeNote(deckID: subdeck.id, front: "hablar", tags: ["verb", "a1"])
    // A brand-new card (step 0, lastReview nil) and a graduated one (step nil, lastReview set):
    // both nil-cases of the FSRS state have to survive the trip.
    let newCard = Card(noteID: note.id, templateIndex: 0, deckID: subdeck.id, createdAt: epoch)
    let reviewedCard = Card(
        id: UUID(), noteID: note.id, templateIndex: 0, deckID: subdeck.id,
        state: .review, step: nil, due: epoch.addingTimeInterval(86_400 * 12),
        stability: 12.3456, difficulty: 5.4321, reps: 7, lapses: 2,
        lastReview: epoch.addingTimeInterval(-3600), createdAt: epoch
    )

    do {
        let container = try store.open()
        let decks = SwiftDataDeckRepository(modelContainer: container)
        let notes = SwiftDataNoteRepository(modelContainer: container)
        let cards = SwiftDataCardRepository(modelContainer: container)

        try await decks.save(deck)
        try await decks.save(subdeck)
        try await notes.save(note)
        try await cards.save(newCard)
        try await cards.save(reviewedCard)
    }

    // Fresh container over the same files.
    let container = try store.open()
    let decks = SwiftDataDeckRepository(modelContainer: container)
    let notes = SwiftDataNoteRepository(modelContainer: container)
    let cards = SwiftDataCardRepository(modelContainer: container)
    let noteTypes = SwiftDataNoteTypeRepository(modelContainer: container)

    #expect(try await decks.allDecks().count == 2)
    #expect(try await decks.deck(id: deck.id) == deck)
    #expect(try await decks.deck(id: subdeck.id) == subdeck)
    #expect(try await notes.note(id: note.id) == note)
    #expect(try await noteTypes.noteType(id: NoteType.basic.id) == NoteType.basic)

    let readBack = try await cards.cards(matching: CardQuery(noteID: note.id))
    #expect(readBack == [newCard, reviewedCard])  // sorted by due ascending
    #expect(readBack[0].step == 0)
    #expect(readBack[0].lastReview == nil)
    #expect(readBack[1].step == nil)
    #expect(readBack[1].lastReview == reviewedCard.lastReview)
}

// MARK: - Cascade

@Test func deckDeleteCascadesButReviewLogsSurvive() async throws {
    let container = try ModelContainer.engramInMemory()
    let decks = SwiftDataDeckRepository(modelContainer: container)
    let notes = SwiftDataNoteRepository(modelContainer: container)
    let cards = SwiftDataCardRepository(modelContainer: container)
    let logs = SwiftDataReviewLogRepository(modelContainer: container)

    let root = makeDeck(name: "Root")
    let child = makeDeck(name: "Child", parentID: root.id)
    let survivor = makeDeck(name: "Untouched")
    let rootNote = makeNote(deckID: root.id, front: "root")
    let childNote = makeNote(deckID: child.id, front: "child")
    let survivorNote = makeNote(deckID: survivor.id, front: "survivor")

    for deck in [root, child, survivor] { try await decks.save(deck) }
    for note in [rootNote, childNote, survivorNote] { try await notes.save(note) }

    var allCards: [Card] = []
    for note in [rootNote, childNote, survivorNote] {
        let card = Card(noteID: note.id, templateIndex: 0, deckID: note.deckID, createdAt: epoch)
        try await cards.save(card)
        try await logs.append(
            ReviewLog(
                cardID: card.id, rating: .good, reviewedAt: epoch, scheduledDays: 1,
                elapsedDays: 0, stateBefore: .new, stabilityAfter: 3.0, difficultyAfter: 5.0
            )
        )
        allCards.append(card)
    }

    try await decks.delete(id: root.id)

    #expect(try await decks.allDecks().map(\.id) == [survivor.id])
    #expect(try await decks.deck(id: child.id) == nil)
    #expect(try await notes.note(id: rootNote.id) == nil)
    #expect(try await notes.note(id: childNote.id) == nil)
    #expect(try await notes.note(id: survivorNote.id) != nil)

    let remaining = try await cards.cards(matching: CardQuery())
    #expect(remaining.map(\.id) == [allCards[2].id])

    // History outlives the cards it describes.
    let history = try await logs.logs(from: .distantPast, to: .distantFuture)
    #expect(history.count == 3)
    #expect(Set(history.map(\.cardID)) == Set(allCards.map(\.id)))
}

// MARK: - CardQuery

@Test func cardQueryFiltersSortsAndLimits() async throws {
    let container = try ModelContainer.engramInMemory()
    let decks = SwiftDataDeckRepository(modelContainer: container)
    let notes = SwiftDataNoteRepository(modelContainer: container)
    let cards = SwiftDataCardRepository(modelContainer: container)

    let deck = makeDeck(name: "Queue")
    let otherDeck = makeDeck(name: "Other")
    try await decks.save(deck)
    try await decks.save(otherDeck)

    let tagged = makeNote(deckID: deck.id, front: "tagged", tags: ["leech"])
    let untagged = makeNote(deckID: deck.id, front: "untagged")
    let elsewhere = makeNote(deckID: otherDeck.id, front: "elsewhere", tags: ["leech"])
    for note in [tagged, untagged, elsewhere] { try await notes.save(note) }

    /// Cards created out of due order, so a passing sort assertion means real sorting.
    func card(_ note: Note, dueDays: Double, state: CardState) -> Card {
        Card(
            id: UUID(), noteID: note.id, templateIndex: 0, deckID: note.deckID,
            state: state, step: nil, due: epoch.addingTimeInterval(86_400 * dueDays),
            stability: 1, difficulty: 5, reps: 1, lapses: 0, lastReview: epoch, createdAt: epoch
        )
    }
    let dueLate = card(tagged, dueDays: 9, state: .review)
    let dueEarly = card(tagged, dueDays: 1, state: .review)
    let dueMiddleLearning = card(tagged, dueDays: 5, state: .learning)
    let untaggedDue = card(untagged, dueDays: 2, state: .review)
    let otherDeckDue = card(elsewhere, dueDays: 3, state: .review)
    for card in [dueLate, dueEarly, dueMiddleLearning, untaggedDue, otherDeckDue] {
        try await cards.save(card)
    }

    let now = epoch.addingTimeInterval(86_400 * 6)

    // deck + due filter, sorted by due ascending
    let queue = try await cards.cards(matching: CardQuery(deckIDs: [deck.id], dueBefore: now))
    #expect(queue.map(\.id) == [dueEarly.id, untaggedDue.id, dueMiddleLearning.id])

    // state filter
    let learning = try await cards.cards(
        matching: CardQuery(deckIDs: [deck.id], states: [.learning], dueBefore: now)
    )
    #expect(learning.map(\.id) == [dueMiddleLearning.id])

    // tag filters through the owning note, across decks
    let leeches = try await cards.cards(matching: CardQuery(tag: "leech", dueBefore: now))
    #expect(leeches.map(\.id) == [dueEarly.id, otherDeckDue.id, dueMiddleLearning.id])

    // limit is applied after filtering and sorting
    let limited = try await cards.cards(
        matching: CardQuery(deckIDs: [deck.id], tag: "leech", dueBefore: now, limit: 1)
    )
    #expect(limited.map(\.id) == [dueEarly.id])

    // dueBefore excludes the future
    #expect(try await cards.cards(matching: CardQuery(noteID: tagged.id)).count == 3)
}

// MARK: - Seeding

@Test func basicNoteTypeSeedingIsIdempotent() async throws {
    let store = TempStore()

    do {
        let noteTypes = SwiftDataNoteTypeRepository(modelContainer: try store.open())
        #expect(try await noteTypes.allNoteTypes() == [NoteType.basic])
    }

    let noteTypes = SwiftDataNoteTypeRepository(modelContainer: try store.open())
    #expect(try await noteTypes.allNoteTypes() == [NoteType.basic])
}

@Test func noteQueryMatchesFieldValuesCaseInsensitively() async throws {
    let container = try ModelContainer.engramInMemory()
    let decks = SwiftDataDeckRepository(modelContainer: container)
    let notes = SwiftDataNoteRepository(modelContainer: container)

    let deck = makeDeck(name: "Browse")
    try await decks.save(deck)
    let hit = makeNote(deckID: deck.id, front: "Hablar", tags: ["verb"])
    let miss = makeNote(deckID: deck.id, front: "comer")
    try await notes.save(hit)
    try await notes.save(miss)

    #expect(try await notes.notes(matching: NoteQuery(text: "habl")).map(\.id) == [hit.id])
    #expect(try await notes.notes(matching: NoteQuery(tag: "verb")).map(\.id) == [hit.id])
    #expect(try await notes.notes(matching: NoteQuery(deckIDs: [UUID()])).isEmpty)
    #expect(try await notes.notes(matching: NoteQuery()).count == 2)
}
