import Foundation
import Testing
import Domain
import Application

private let start = Date(timeIntervalSince1970: 1_735_732_800)

@Suite("Undo + daily limits")
struct ReviewSessionUndoAndLimitsTests {
    private func fixture() -> (InMemoryStore, ReviewSessionService, Deck) {
        let store = InMemoryStore()
        let deck = Deck(name: "Math", createdAt: start)
        let service = ReviewSessionService(
            deckRepository: InMemoryDeckRepository(store: store),
            cardRepository: InMemoryCardRepository(store: store),
            noteRepository: InMemoryNoteRepository(store: store),
            noteTypeRepository: InMemoryNoteTypeRepository(store: store),
            reviewLogRepository: InMemoryReviewLogRepository(store: store)
        )
        return (store, service, deck)
    }

    private func seed(_ store: InMemoryStore, deck: Deck, count: Int) async {
        var notes: [Note] = []
        var cards: [Card] = []
        for i in 0..<count {
            let note = Note(
                noteTypeID: NoteType.basic.id, deckID: deck.id,
                fields: ["front": "q\(i)", "back": "a\(i)"], createdAt: start, modifiedAt: start
            )
            notes.append(note)
            cards.append(contentsOf: NoteType.basic.makeCards(for: note, createdAt: start))
        }
        await store.seed(decks: [deck], noteTypes: [.basic], notes: notes, cards: cards)
    }

    @Test func undoRestoresCardLogAndQueue() async throws {
        let (store, session, deck) = fixture()
        await seed(store, deck: deck, count: 1)
        try await session.start(scope: .all, now: start)
        let before = try #require(await session.currentItem)

        try await session.grade(.good, now: start)
        #expect(await session.progress.completed == 1)
        #expect(await store.logs.count == 1)

        #expect(try await session.undoLast())
        #expect(await session.progress.completed == 0)
        #expect(await session.progress.correct == 0)
        #expect(await store.logs.isEmpty)
        // Learning re-queue copy is gone, original item is back in front, FSRS state restored.
        #expect(await session.progress.remaining == 1)
        let restored = try #require(await session.currentItem)
        #expect(restored.card == before.card)
        #expect(await store.cards[before.card.id] == before.card)
        // Nothing left to undo.
        #expect(try await session.undoLast() == false)
    }

    @Test func dailyLimitsSubtractTodaysWork() async throws {
        let (store, session, deck) = fixture()
        await seed(store, deck: deck, count: 10)
        var limited = deck
        limited.config.newCardsPerDay = 4
        await store.setDeck(limited)

        // Three cards were already introduced earlier today.
        for _ in 0..<3 {
            await store.appendLog(ReviewLog(
                cardID: UUID(), rating: .good, reviewedAt: start.addingTimeInterval(-3_600),
                scheduledDays: 0, elapsedDays: 0, stateBefore: .new,
                stabilityAfter: 1, difficultyAfter: 5
            ))
        }
        try await session.start(scope: .deck(limited.id), now: start)
        #expect(await session.progress.remaining == 1) // 4 - 3 already done

        // Yesterday's work does not count against today.
        let fresh = fixture()
        await seed(fresh.0, deck: fresh.2, count: 10)
        var freshDeck = fresh.2
        freshDeck.config.newCardsPerDay = 4
        await fresh.0.setDeck(freshDeck)
        await fresh.0.appendLog(ReviewLog(
            cardID: UUID(), rating: .good, reviewedAt: start.addingTimeInterval(-86_400 * 2),
            scheduledDays: 0, elapsedDays: 0, stateBefore: .new,
            stabilityAfter: 1, difficultyAfter: 5
        ))
        try await fresh.1.start(scope: .deck(freshDeck.id), now: start)
        #expect(await fresh.1.progress.remaining == 4)
    }
}

@Suite("CramSession")
struct CramSessionTests {
    private func fixture() async -> (InMemoryStore, CramSession, Deck) {
        let store = InMemoryStore()
        let deck = Deck(name: "Math", createdAt: start)
        var notes: [Note] = []
        var cards: [Card] = []
        for i in 0..<3 {
            let note = Note(
                noteTypeID: NoteType.basic.id, deckID: deck.id,
                fields: ["front": "q\(i)", "back": "a\(i)"], createdAt: start, modifiedAt: start
            )
            notes.append(note)
            // One future-scheduled card proves cram ignores due dates.
            var card = NoteType.basic.makeCards(for: note, createdAt: start)[0]
            if i == 0 { card.due = start.addingTimeInterval(86_400 * 30); card.state = .review }
            cards.append(card)
        }
        await store.seed(decks: [deck], noteTypes: [.basic], notes: notes, cards: cards)
        let session = CramSession(
            deckRepository: InMemoryDeckRepository(store: store),
            cardRepository: InMemoryCardRepository(store: store),
            noteRepository: InMemoryNoteRepository(store: store),
            noteTypeRepository: InMemoryNoteTypeRepository(store: store)
        )
        return (store, session, deck)
    }

    @Test func cramWalksEverythingWithoutTouchingScheduling() async throws {
        let (store, session, deck) = await fixture()
        let cardsBefore = await store.cards
        try await session.start(scope: .deck(deck.id), now: start)
        #expect(await session.progress.remaining == 3) // future card included
        #expect(await session.previewIntervals(now: start).isEmpty)

        try await session.grade(.again, now: start) // goes to the back
        try await session.grade(.good, now: start)
        try await session.grade(.good, now: start)
        try await session.grade(.good, now: start) // the again-card again
        #expect(await session.progress.remaining == 0)
        #expect(await session.progress.completed == 4)
        #expect(await session.progress.correct == 3)

        // Zero persistence: FSRS state and logs untouched.
        #expect(await store.cards == cardsBefore)
        #expect(await store.logs.isEmpty)
    }

    @Test func cramUndoRestoresQueue() async throws {
        let (_, session, deck) = await fixture()
        try await session.start(scope: .deck(deck.id), now: start)
        let first = try #require(await session.currentItem)
        try await session.grade(.again, now: start)
        #expect(try await session.undoLast())
        #expect(await session.currentItem == first)
        #expect(await session.progress.completed == 0)
        #expect(await session.progress.remaining == 3)
    }
}

@Suite("DeckService card re-sync")
struct DeckServiceResyncTests {
    @Test func editingClozeMarkersGrowsAndShrinksCards() async throws {
        let store = InMemoryStore()
        let deck = Deck(name: "Math", createdAt: start)
        await store.seed(decks: [deck], noteTypes: [.cloze])
        let service = DeckService(
            deckRepository: InMemoryDeckRepository(store: store),
            cardRepository: InMemoryCardRepository(store: store),
            noteRepository: InMemoryNoteRepository(store: store),
            noteTypeRepository: InMemoryNoteTypeRepository(store: store)
        )

        var note = try await service.addNote(
            deckID: deck.id, noteType: .cloze,
            fields: ["text": "{{c1::uno}} y {{c2::dos}}"], now: start
        )
        #expect(await store.cards.count == 2)
        let keptCard = await store.cards.values.first { $0.templateIndex == 0 }

        // Add c3, drop c2: one card grows, one dies, c1's card (and its FSRS state) survives.
        note.fields["text"] = "{{c1::uno}} y {{c3::tres}}"
        try await service.updateNote(note, now: start.addingTimeInterval(60))
        let indices = await store.cards.values.map(\.templateIndex).sorted()
        #expect(indices == [0, 2])
        #expect(await store.cards[keptCard!.id] == keptCard)
    }
}
