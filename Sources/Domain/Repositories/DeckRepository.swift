import Foundation

/// Persistence seam for decks. Implementations live in Infrastructure.
public protocol DeckRepository: Sendable {
    func allDecks() async throws -> [Deck]
    func deck(id: UUID) async throws -> Deck?
    func save(_ deck: Deck) async throws
    /// Must cascade: subdecks, their notes and cards (SwiftData delete rules at M2).
    func delete(id: UUID) async throws
}
