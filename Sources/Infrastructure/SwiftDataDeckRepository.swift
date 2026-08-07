import Domain
import Foundation
import SwiftData

@ModelActor
public actor SwiftDataDeckRepository: DeckRepository {
    public func allDecks() throws -> [Deck] {
        try modelContext.fetch(FetchDescriptor<SDDeck>()).map { $0.toDomain() }
    }

    public func deck(id: UUID) throws -> Deck? {
        try fetchDeck(id: id)?.toDomain()
    }

    public func save(_ deck: Deck) throws {
        let stored: SDDeck
        if let existing = try fetchDeck(id: deck.id) {
            existing.apply(deck)
            stored = existing
        } else {
            stored = SDDeck(deck)
            modelContext.insert(stored)
        }
        // Resolving the parent here is what makes the cascade work; a dangling
        // parentID just leaves the deck at the root rather than failing the save.
        stored.parent = deck.parentID.flatMap { try? fetchDeck(id: $0) }
        try modelContext.save()
    }

    /// SwiftData does the cascade: deck -> children -> notes -> cards.
    /// `SDReviewLog` has no relationship to any of them, so history survives.
    public func delete(id: UUID) throws {
        guard let stored = try fetchDeck(id: id) else { return }
        modelContext.delete(stored)
        try modelContext.save()
    }

    private func fetchDeck(id: UUID) throws -> SDDeck? {
        var descriptor = FetchDescriptor<SDDeck>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
