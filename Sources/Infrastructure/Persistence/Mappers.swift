import Domain
import Foundation

// SD <-> Domain mapping, in one file so the whole persistence boundary reads in a
// single sitting. `apply(_:)` is the upsert half: repositories fetch-or-insert and
// then overwrite every mapped field, so a saved domain value is authoritative.
//
// Enums cross the boundary as raw values; unknown raws fall back to the zero case
// rather than throwing — a corrupt row should not take the whole queue down.

private let jsonEncoder = JSONEncoder()
private let jsonDecoder = JSONDecoder()

// MARK: - Deck

extension SDDeck {
    convenience init(_ deck: Deck) {
        self.init(
            id: deck.id, name: deck.name, createdAt: deck.createdAt,
            requestRetention: deck.config.requestRetention,
            newCardsPerDay: deck.config.newCardsPerDay,
            maxReviewsPerDay: deck.config.maxReviewsPerDay
        )
    }

    /// Overwrites the scalar fields. The `parent` relationship is wired by the
    /// repository, which is the only place that can resolve `parentID`.
    func apply(_ deck: Deck) {
        name = deck.name
        createdAt = deck.createdAt
        requestRetention = deck.config.requestRetention
        newCardsPerDay = deck.config.newCardsPerDay
        maxReviewsPerDay = deck.config.maxReviewsPerDay
    }

    func toDomain() -> Deck {
        Deck(
            id: id, name: name, parentID: parent?.id,
            config: DeckConfig(
                requestRetention: requestRetention,
                newCardsPerDay: newCardsPerDay,
                maxReviewsPerDay: maxReviewsPerDay
            ),
            createdAt: createdAt
        )
    }
}

// MARK: - NoteType

extension SDNoteType {
    convenience init(_ noteType: NoteType) throws {
        self.init(
            id: noteType.id, name: noteType.name, kindRaw: noteType.kind.rawValue,
            fieldsData: try jsonEncoder.encode(noteType.fields),
            templatesData: try jsonEncoder.encode(noteType.templates)
        )
    }

    func apply(_ noteType: NoteType) throws {
        name = noteType.name
        kindRaw = noteType.kind.rawValue
        fieldsData = try jsonEncoder.encode(noteType.fields)
        templatesData = try jsonEncoder.encode(noteType.templates)
    }

    func toDomain() throws -> NoteType {
        NoteType(
            id: id, name: name,
            kind: NoteTypeKind(rawValue: kindRaw) ?? .basic,
            fields: try jsonDecoder.decode([FieldDef].self, from: fieldsData),
            templates: try jsonDecoder.decode([CardTemplate].self, from: templatesData)
        )
    }
}

// MARK: - Note

extension SDNote {
    convenience init(_ note: Note) {
        self.init(
            id: note.id, noteTypeID: note.noteTypeID, deckID: note.deckID,
            fields: note.fields, tags: note.tags,
            createdAt: note.createdAt, modifiedAt: note.modifiedAt
        )
    }

    /// The `deck` relationship is wired by the repository; `deckID` stays in sync here.
    func apply(_ note: Note) {
        noteTypeID = note.noteTypeID
        deckID = note.deckID
        fields = note.fields
        tags = note.tags
        createdAt = note.createdAt
        modifiedAt = note.modifiedAt
    }

    func toDomain() -> Note {
        Note(
            id: id, noteTypeID: noteTypeID, deckID: deckID,
            fields: fields, tags: tags,
            createdAt: createdAt, modifiedAt: modifiedAt
        )
    }
}

// MARK: - Card

extension SDCard {
    convenience init(_ card: Card) {
        self.init(
            id: card.id, noteID: card.noteID, templateIndex: card.templateIndex,
            deckID: card.deckID, stateRaw: card.state.rawValue, step: card.step,
            due: card.due, stability: card.stability, difficulty: card.difficulty,
            reps: card.reps, lapses: card.lapses, lastReview: card.lastReview,
            createdAt: card.createdAt
        )
    }

    func apply(_ card: Card) {
        noteID = card.noteID
        templateIndex = card.templateIndex
        deckID = card.deckID
        stateRaw = card.state.rawValue
        step = card.step
        due = card.due
        stability = card.stability
        difficulty = card.difficulty
        reps = card.reps
        lapses = card.lapses
        lastReview = card.lastReview
        createdAt = card.createdAt
    }

    func toDomain() -> Card {
        Card(
            id: id, noteID: noteID, templateIndex: templateIndex, deckID: deckID,
            state: CardState(rawValue: stateRaw) ?? .new, step: step, due: due,
            stability: stability, difficulty: difficulty, reps: reps, lapses: lapses,
            lastReview: lastReview, createdAt: createdAt
        )
    }
}

// MARK: - ReviewLog

extension SDReviewLog {
    convenience init(_ log: ReviewLog) {
        self.init(
            id: log.id, cardID: log.cardID, ratingRaw: log.rating.rawValue,
            reviewedAt: log.reviewedAt, scheduledDays: log.scheduledDays,
            elapsedDays: log.elapsedDays, stateBeforeRaw: log.stateBefore.rawValue,
            stabilityAfter: log.stabilityAfter, difficultyAfter: log.difficultyAfter
        )
    }

    func toDomain() -> ReviewLog {
        ReviewLog(
            id: id, cardID: cardID, rating: Rating(rawValue: ratingRaw) ?? .again,
            reviewedAt: reviewedAt, scheduledDays: scheduledDays, elapsedDays: elapsedDays,
            stateBefore: CardState(rawValue: stateBeforeRaw) ?? .new,
            stabilityAfter: stabilityAfter, difficultyAfter: difficultyAfter
        )
    }
}
