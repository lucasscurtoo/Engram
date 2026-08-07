import Foundation
import Testing
import Domain

private let start = Date(timeIntervalSince1970: 1_735_732_800)

@Suite("Note/NoteType seam")
struct NoteTypeTests {
    @Test func basicNoteGeneratesExactlyOneCard() {
        let note = Note(
            noteTypeID: NoteType.basic.id, deckID: UUID(),
            fields: ["front": "**2+2**", "back": "4"], createdAt: start, modifiedAt: start
        )
        let cards = NoteType.basic.makeCards(for: note, createdAt: start)
        #expect(cards.count == 1)
        #expect(cards[0].noteID == note.id)
        #expect(cards[0].templateIndex == 0)
        #expect(cards[0].deckID == note.deckID)
        #expect(cards[0].state == .new)
    }

    @Test func fieldResolutionGoesThroughTemplates() {
        let note = Note(
            noteTypeID: NoteType.basic.id, deckID: UUID(),
            fields: ["front": "q", "back": "a"], createdAt: start, modifiedAt: start
        )
        let front = NoteType.basic.frontFields(of: note, templateIndex: 0)
        let back = NoteType.basic.backFields(of: note, templateIndex: 0)
        #expect(front.map(\.content) == ["q"])
        #expect(back.map(\.content) == ["a"])
        #expect(front[0].def.contentType == .markdown)
    }

    @Test func missingFieldResolvesToEmptyNotCrash() {
        let note = Note(
            noteTypeID: NoteType.basic.id, deckID: UUID(),
            fields: ["front": "q"], createdAt: start, modifiedAt: start
        )
        #expect(NoteType.basic.backFields(of: note, templateIndex: 0).map(\.content) == [""])
    }
}

@Suite("DeckTree")
struct DeckTreeTests {
    @Test func subtreeAndFullName() {
        let math = Deck(name: "Math", createdAt: start)
        let algebra = Deck(name: "Algebra", parentID: math.id, createdAt: start)
        let linear = Deck(name: "Linear", parentID: algebra.id, createdAt: start)
        let other = Deck(name: "Spanish", createdAt: start)
        let decks = [math, algebra, linear, other]

        #expect(DeckTree.subtreeIDs(of: math.id, in: decks) == [math.id, algebra.id, linear.id])
        #expect(DeckTree.subtreeIDs(of: other.id, in: decks) == [other.id])
        #expect(DeckTree.fullName(of: linear.id, in: decks) == "Math::Algebra::Linear")
    }

    @Test func cyclesDoNotHang() {
        var a = Deck(name: "A", createdAt: start)
        var b = Deck(name: "B", createdAt: start)
        a.parentID = b.id
        b.parentID = a.id
        let subtree = DeckTree.subtreeIDs(of: a.id, in: [a, b])
        #expect(subtree.contains(a.id) && subtree.contains(b.id))
        _ = DeckTree.fullName(of: a.id, in: [a, b]) // must terminate
    }
}
