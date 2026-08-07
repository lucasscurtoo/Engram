import Foundation
import SwiftData

/// Persistence mirror of `Domain.Note`. Owns its cards (cascade delete); the cards'
/// review logs are standalone history and outlive it.
@Model
public final class SDNote {
    public var id: UUID = UUID()
    public var noteTypeID: UUID = UUID()
    /// Denormalized from `deck` so note/card queries stay flat scalar predicates.
    /// Kept in sync by `SDNote.apply(_:)` — never write one without the other.
    public var deckID: UUID = UUID()
    public var fields: [String: String] = [:]
    public var tags: [String] = []
    public var createdAt: Date = Date()
    public var modifiedAt: Date = Date()

    public var deck: SDDeck?

    @Relationship(deleteRule: .cascade, inverse: \SDCard.note)
    public var cards: [SDCard] = []

    public init(
        id: UUID, noteTypeID: UUID, deckID: UUID,
        fields: [String: String], tags: [String],
        createdAt: Date, modifiedAt: Date
    ) {
        self.id = id
        self.noteTypeID = noteTypeID
        self.deckID = deckID
        self.fields = fields
        self.tags = tags
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
