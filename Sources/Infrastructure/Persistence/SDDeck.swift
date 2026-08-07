import Foundation
import SwiftData

/// Persistence mirror of `Domain.Deck`.
///
/// The subdeck hierarchy is a self-relation so SwiftData does the cascade for us:
/// deleting a deck deletes its children, and each deck cascades into its notes,
/// which cascade into their cards. Review logs are standalone and survive.
///
// ponytail: no `@Attribute(.unique)` on `id` — repositories upsert by explicit
// fetch anyway (they need partial updates), and unique constraints + relationships
// are a known source of SwiftData surprises. Add `#Index` if queue queries get slow
// (requires raising the deployment target to macOS 15).
@Model
public final class SDDeck {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date()

    // DeckConfig, inlined.
    public var requestRetention: Double = 0.9
    public var newCardsPerDay: Int = 20
    public var maxReviewsPerDay: Int = 200

    public var parent: SDDeck?

    @Relationship(deleteRule: .cascade, inverse: \SDDeck.parent)
    public var children: [SDDeck] = []

    @Relationship(deleteRule: .cascade, inverse: \SDNote.deck)
    public var notes: [SDNote] = []

    public init(
        id: UUID, name: String, createdAt: Date,
        requestRetention: Double, newCardsPerDay: Int, maxReviewsPerDay: Int
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.requestRetention = requestRetention
        self.newCardsPerDay = newCardsPerDay
        self.maxReviewsPerDay = maxReviewsPerDay
    }
}
