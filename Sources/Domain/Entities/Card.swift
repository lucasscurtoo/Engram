import Foundation

/// The unit of scheduling. Content lives in the owning `Note`; a card only knows
/// which note and which template generated it. Never store front/back here.
public struct Card: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public var noteID: UUID
    public var templateIndex: Int
    /// Denormalized from the note for cheap queue queries.
    public var deckID: UUID

    // MARK: FSRS state
    public var state: CardState
    /// Index into learning/relearning steps; nil once graduated to `.review`.
    /// Not in the brief's sketch, but required to reproduce py-fsrs step scheduling exactly.
    public var step: Int?
    public var due: Date
    /// Undefined (0) while `.new`; set on first review.
    public var stability: Double
    /// Undefined (0) while `.new`; clamped to 1...10 afterwards.
    public var difficulty: Double
    public var reps: Int
    public var lapses: Int
    public var lastReview: Date?
    public var createdAt: Date

    /// A brand-new card, due immediately.
    public init(id: UUID = UUID(), noteID: UUID, templateIndex: Int, deckID: UUID, createdAt: Date) {
        self.init(
            id: id, noteID: noteID, templateIndex: templateIndex, deckID: deckID,
            state: .new, step: 0, due: createdAt, stability: 0, difficulty: 0,
            reps: 0, lapses: 0, lastReview: nil, createdAt: createdAt
        )
    }

    /// Full initializer for persistence mappers and tests.
    public init(
        id: UUID, noteID: UUID, templateIndex: Int, deckID: UUID,
        state: CardState, step: Int?, due: Date, stability: Double, difficulty: Double,
        reps: Int, lapses: Int, lastReview: Date?, createdAt: Date
    ) {
        self.id = id
        self.noteID = noteID
        self.templateIndex = templateIndex
        self.deckID = deckID
        self.state = state
        self.step = step
        self.due = due
        self.stability = stability
        self.difficulty = difficulty
        self.reps = reps
        self.lapses = lapses
        self.lastReview = lastReview
        self.createdAt = createdAt
    }
}
