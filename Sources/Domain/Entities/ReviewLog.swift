import Foundation

/// Immutable record of one review. Feeds stats now and future FSRS weight optimization.
public struct ReviewLog: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let cardID: UUID
    public let rating: Rating
    public let reviewedAt: Date
    /// Whole days of the interval that was assigned (0 for intra-day learning steps).
    public let scheduledDays: Int
    /// Whole days since the previous review (0 for the first one).
    public let elapsedDays: Int
    public let stateBefore: CardState
    public let stabilityAfter: Double
    public let difficultyAfter: Double

    public init(
        id: UUID = UUID(), cardID: UUID, rating: Rating, reviewedAt: Date,
        scheduledDays: Int, elapsedDays: Int, stateBefore: CardState,
        stabilityAfter: Double, difficultyAfter: Double
    ) {
        self.id = id
        self.cardID = cardID
        self.rating = rating
        self.reviewedAt = reviewedAt
        self.scheduledDays = scheduledDays
        self.elapsedDays = elapsedDays
        self.stateBefore = stateBefore
        self.stabilityAfter = stabilityAfter
        self.difficultyAfter = difficultyAfter
    }
}
