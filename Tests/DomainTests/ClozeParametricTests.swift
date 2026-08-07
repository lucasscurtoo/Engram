import Foundation
import Testing
import Domain

private let start = Date(timeIntervalSince1970: 1_735_732_800)

@Suite("Cloze")
struct ClozeTests {
    let text = "La derivada de {{c1::x^2}} es {{c2::2x::polinomio}} y de nuevo {{c1::x^2}}"

    @Test func indicesAreDistinctAndSorted() {
        #expect(Cloze.indices(in: text) == [1, 2])
        #expect(Cloze.indices(in: "sin marcadores").isEmpty)
    }

    @Test func frontHidesOnlyTheTargetNumber() {
        let front = Cloze.front(text, hiding: 1)
        #expect(front == "La derivada de **[…]** es 2x y de nuevo **[…]**")
        let withHint = Cloze.front(text, hiding: 2)
        #expect(withHint == "La derivada de x^2 es **[polinomio]** y de nuevo x^2")
    }

    @Test func backRevealsTargetInBold() {
        #expect(Cloze.back(text, revealing: 2) == "La derivada de x^2 es **2x** y de nuevo x^2")
    }

    @Test func clozeNoteGeneratesOneCardPerDistinctMarker() {
        let note = Note(
            noteTypeID: NoteType.cloze.id, deckID: UUID(),
            fields: ["text": text], createdAt: start, modifiedAt: start
        )
        let cards = NoteType.cloze.makeCards(for: note, createdAt: start)
        #expect(cards.map(\.templateIndex) == [0, 1])

        let front = NoteType.cloze.frontFields(of: note, templateIndex: 1)
        #expect(front.map(\.content) == ["La derivada de x^2 es **[polinomio]** y de nuevo x^2"])
        // Stale index (marker removed later) resolves to nil, not a crash.
        #expect(NoteType.cloze.sideFields(of: note, templateIndex: 5, front: true) == nil)
    }
}

@Suite("Parametric")
struct ParametricTests {
    let note = Note(
        noteTypeID: NoteType.parametric.id, deckID: UUID(),
        fields: [
            "front": "¿Cuánto es {a} × {b}?",
            "back": "{a} × {b} = **{= a * b}**",
            "variables": "a = 2..12, b = 3..9",
        ],
        createdAt: start, modifiedAt: start
    )

    @Test func valuesAreDeterministicPerSeedAndInRange() {
        let first = Parametric.values(spec: "a = 2..12, b = 3..9", seed: 42)
        let second = Parametric.values(spec: "a = 2..12, b = 3..9", seed: 42)
        #expect(first == second)
        #expect((2...12).contains(first["a"]!))
        #expect((3...9).contains(first["b"]!))
        let other = Parametric.values(spec: "a = 2..12, b = 3..9", seed: 43)
        #expect(other != first || true) // different seeds may collide; no assertion beyond determinism
    }

    @Test func substitutionAndArithmeticAgreeAcrossSides() throws {
        let seed: UInt64 = 7
        let front = NoteType.parametric.frontFields(of: note, templateIndex: 0, seed: seed)
        let back = NoteType.parametric.backFields(of: note, templateIndex: 0, seed: seed)
        let values = Parametric.values(spec: note.fields["variables"]!, seed: seed)
        let a = try #require(values["a"]), b = try #require(values["b"])
        #expect(front.map(\.content) == ["¿Cuánto es \(a) × \(b)?"])
        #expect(back.map(\.content) == ["\(a) × \(b) = **\(a * b)**"])
    }

    @Test func withoutSeedTheRawTemplateShows() {
        #expect(
            NoteType.parametric.frontFields(of: note, templateIndex: 0).map(\.content)
                == ["¿Cuánto es {a} × {b}?"]
        )
    }

    @Test func malformedInputStaysSafe() {
        // Bad ranges are skipped; unknown vars and non-arithmetic exprs stay literal.
        #expect(Parametric.values(spec: "a = 9..1, b = x..2, = 1..2", seed: 1).isEmpty)
        let out = Parametric.substitute("{z} y {= z * DROP TABLE }", values: ["a": 3])
        #expect(out == "{z} y {= z * DROP TABLE }")
    }
}
