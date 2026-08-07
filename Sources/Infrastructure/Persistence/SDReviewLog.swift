import Foundation
import SwiftData

/// Persistence mirror of `Domain.ReviewLog`.
///
/// Deliberately standalone: `cardID` is a plain scalar, NOT a relationship. Review logs
/// are immutable history and must survive deletion of their card, note and deck
/// (`ReviewLogRepository` docs). A relationship would either cascade them away or
/// leave dangling nullified rows.
@Model
public final class SDReviewLog {
    public var id: UUID = UUID()
    public var cardID: UUID = UUID()
    /// `Rating` raw value.
    public var ratingRaw: Int = 0
    public var reviewedAt: Date = Date()
    public var scheduledDays: Int = 0
    public var elapsedDays: Int = 0
    /// `CardState` raw value before the review.
    public var stateBeforeRaw: Int = 0
    public var stabilityAfter: Double = 0
    public var difficultyAfter: Double = 0

    public init(
        id: UUID, cardID: UUID, ratingRaw: Int, reviewedAt: Date,
        scheduledDays: Int, elapsedDays: Int, stateBeforeRaw: Int,
        stabilityAfter: Double, difficultyAfter: Double
    ) {
        self.id = id
        self.cardID = cardID
        self.ratingRaw = ratingRaw
        self.reviewedAt = reviewedAt
        self.scheduledDays = scheduledDays
        self.elapsedDays = elapsedDays
        self.stateBeforeRaw = stateBeforeRaw
        self.stabilityAfter = stabilityAfter
        self.difficultyAfter = difficultyAfter
    }
}
