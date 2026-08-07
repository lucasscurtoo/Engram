import Foundation
import Testing
import Domain
import Application

private let start = Date(timeIntervalSince1970: 1_735_732_800)

@Suite("ReviewSessionService")
struct ReviewSessionServiceTests {
    struct Fixture {
        let store = InMemoryStore()
        let deck = Deck(name: "Math", createdAt: start)
        var service: ReviewSessionService {
            ReviewSessionService(
                scheduler: FSRS(),
                deckRepository: InMemoryDeckRepository(store: store),
                cardRepository: InMemoryCardRepository(store: store),
                noteRepository: InMemoryNoteRepository(store: store),
                noteTypeRepository: InMemoryNoteTypeRepository(store: store),
                reviewLogRepository: InMemoryReviewLogRepository(store: store)
            )
        }

        /// Seeds one Basic note (with its generated card) per fields dict.
        func seed(notesFields: [[String: String]], tags: [String] = []) async {
            var notes: [Note] = []
            var cards: [Card] = []
            for fields in notesFields {
                let note = Note(
                    noteTypeID: NoteType.basic.id, deckID: deck.id,
                    fields: fields, tags: tags, createdAt: start, modifiedAt: start
                )
                notes.append(note)
                cards.append(contentsOf: NoteType.basic.makeCards(for: note, createdAt: start))
            }
            await store.seed(decks: [deck], noteTypes: [.basic], notes: notes, cards: cards)
        }
    }

    @Test func startBuildsQueueFromNewCards() async throws {
        let fixture = Fixture()
        await fixture.seed(notesFields: [["front": "2+2", "back": "4"], ["front": "3*3", "back": "9"]])
        let session = fixture.service
        try await session.start(scope: .deck(fixture.deck.id), now: start)
        #expect(await session.progress.remaining == 2)
        #expect(await session.currentItem?.noteType.id == NoteType.basic.id)
    }

    @Test func gradingPersistsCardAndLogAndRequeuesLearningCards() async throws {
        let fixture = Fixture()
        await fixture.seed(notesFields: [["front": "2+2", "back": "4"]])
        let session = fixture.service
        try await session.start(scope: .all, now: start)

        try await session.grade(.good, now: start) // new -> learning step 1, re-queued
        #expect(await session.progress.completed == 1)
        #expect(await session.progress.remaining == 1)

        let requeued = try #require(await session.currentItem)
        #expect(requeued.card.state == .learning)
        try await session.grade(.good, now: start.addingTimeInterval(600)) // graduates
        #expect(await session.progress.remaining == 0)
        #expect(await session.progress.correct == 2)

        let persisted = try #require(await fixture.store.cards[requeued.card.id])
        #expect(persisted.state == .review)
        #expect(persisted.due > start.addingTimeInterval(86_400))
        let logs = await fixture.store.logs
        #expect(logs.count == 2)
        #expect(logs[0].stateBefore == .new)
        #expect(logs[1].stateBefore == .learning)
    }

    @Test func tagScopeFiltersThroughNotes() async throws {
        let fixture = Fixture()
        await fixture.seed(notesFields: [["front": "1/2 + 1/4", "back": "3/4"]], tags: ["fractions"])
        let session = fixture.service
        try await session.start(scope: .tag("algebra"), now: start)
        #expect(await session.progress.remaining == 0)
        try await session.start(scope: .tag("fractions"), now: start)
        #expect(await session.progress.remaining == 1)
    }

    @Test func deckScopeIncludesSubdecks() async throws {
        let fixture = Fixture()
        await fixture.seed(notesFields: [["front": "x", "back": "y"]])
        let sub = Deck(name: "Algebra", parentID: fixture.deck.id, createdAt: start)
        let subNote = Note(
            noteTypeID: NoteType.basic.id, deckID: sub.id,
            fields: ["front": "a", "back": "b"], createdAt: start, modifiedAt: start
        )
        await fixture.store.seed(
            decks: [sub], notes: [subNote],
            cards: NoteType.basic.makeCards(for: subNote, createdAt: start)
        )
        let session = fixture.service
        try await session.start(scope: .deck(fixture.deck.id), now: start)
        #expect(await session.progress.remaining == 2)
    }

    @Test func newCardLimitComesFromDeckConfig() async throws {
        let fixture = Fixture()
        await fixture.seed(notesFields: (1...5).map { ["front": "q\($0)", "back": "a\($0)"] })
        var limited = fixture.deck
        limited.config.newCardsPerDay = 3
        await fixture.store.setDeck(limited)
        let session = fixture.service
        try await session.start(scope: .deck(limited.id), now: start)
        #expect(await session.progress.remaining == 3)
    }
}
