import Foundation
import Domain

/// Cram/practice mode (seam 3): walks EVERY card in scope, shuffled, without
/// touching FSRS state, review logs, or stats — study for tomorrow's exam without
/// contaminating the long-term schedule. `Again` sends the card to the back of the
/// queue until it sticks; anything else retires it for the session.
public actor CramSession: StudySession {
    private let deckRepository: any DeckRepository
    private let cardRepository: any CardRepository
    private let noteRepository: any NoteRepository
    private let noteTypeRepository: any NoteTypeRepository

    private var queue: [StudyItem] = []
    private var completed = 0
    private var correct = 0
    private var history: [(item: StudyItem, again: Bool)] = []

    public init(
        deckRepository: any DeckRepository,
        cardRepository: any CardRepository,
        noteRepository: any NoteRepository,
        noteTypeRepository: any NoteTypeRepository
    ) {
        self.deckRepository = deckRepository
        self.cardRepository = cardRepository
        self.noteRepository = noteRepository
        self.noteTypeRepository = noteTypeRepository
    }

    public var currentItem: StudyItem? { queue.first }

    public var progress: StudyProgress {
        StudyProgress(completed: completed, correct: correct, remaining: queue.count)
    }

    public func start(scope: StudyScope, now: Date) async throws {
        completed = 0
        correct = 0
        history = []
        let (deckIDs, tag) = try await resolve(scope: scope)
        let cards = try await cardRepository.cards(matching: CardQuery(deckIDs: deckIDs, tag: tag))
        queue = try await items(for: cards).shuffled()
    }

    /// No scheduling in cram — the UI hides interval captions on empty.
    public func previewIntervals(now: Date) -> [Rating: TimeInterval] { [:] }

    public func grade(_ rating: Rating, now: Date) async throws {
        guard let item = currentItem else { return }
        queue.removeFirst()
        completed += 1
        let again = rating == .again
        if again {
            queue.append(item)
        } else {
            correct += 1
        }
        history.append((item: item, again: again))
    }

    @discardableResult
    public func undoLast() async throws -> Bool {
        guard let last = history.popLast() else { return false }
        if last.again, let index = queue.lastIndex(of: last.item) {
            queue.remove(at: index)
        } else {
            correct -= 1
        }
        completed -= 1
        queue.insert(last.item, at: 0)
        return true
    }

    // MARK: - Private

    private func resolve(scope: StudyScope) async throws -> ([UUID]?, String?) {
        switch scope {
        case .all:
            (nil, nil)
        case .tag(let tag):
            (nil, tag)
        case .deck(let id):
            (Array(DeckTree.subtreeIDs(of: id, in: try await deckRepository.allDecks())), nil)
        }
    }

    private func items(for cards: [Card]) async throws -> [StudyItem] {
        var noteCache: [UUID: Note] = [:]
        var typeCache: [UUID: NoteType] = [:]
        var result: [StudyItem] = []
        for card in cards {
            var note = noteCache[card.noteID]
            if note == nil {
                note = try await noteRepository.note(id: card.noteID)
            }
            guard let note else { continue }
            var type = typeCache[note.noteTypeID]
            if type == nil {
                type = try await noteTypeRepository.noteType(id: note.noteTypeID)
            }
            guard let type else { continue }
            noteCache[note.id] = note
            typeCache[type.id] = type
            result.append(StudyItem(
                card: card, note: note, noteType: type,
                parametricSeed: type.kind == .parametric ? UInt64.random(in: .min ... .max) : nil
            ))
        }
        return result
    }
}
