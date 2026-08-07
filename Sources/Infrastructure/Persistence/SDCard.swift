import Foundation
import SwiftData

/// Persistence mirror of `Domain.Card`: the full FSRS state, nothing renderable.
/// `deckID` is denormalized from the owning note so the queue query is one flat fetch.
@Model
public final class SDCard {
    public var id: UUID = UUID()
    public var noteID: UUID = UUID()
    public var templateIndex: Int = 0
    public var deckID: UUID = UUID()

    /// `CardState` raw value.
    public var stateRaw: Int = 0
    /// Learning/relearning step index; nil once graduated.
    public var step: Int?
    public var due: Date = Date()
    public var stability: Double = 0
    public var difficulty: Double = 0
    public var reps: Int = 0
    public var lapses: Int = 0
    public var lastReview: Date?
    public var createdAt: Date = Date()

    public var note: SDNote?

    public init(
        id: UUID, noteID: UUID, templateIndex: Int, deckID: UUID,
        stateRaw: Int, step: Int?, due: Date, stability: Double, difficulty: Double,
        reps: Int, lapses: Int, lastReview: Date?, createdAt: Date
    ) {
        self.id = id
        self.noteID = noteID
        self.templateIndex = templateIndex
        self.deckID = deckID
        self.stateRaw = stateRaw
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
