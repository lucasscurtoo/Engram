import Domain
import Foundation
import SwiftData

@ModelActor
public actor SwiftDataCardRepository: CardRepository {
    public func cards(matching query: CardQuery) throws -> [Card] {
        // #Predicate is a macro: it cannot be assembled conditionally, and optionals
        // inside it are hostile. So every filter is normalized to a captured constant
        // plus an "any" escape hatch — no optionals, one predicate, still SQL-side.
        let anyDeck = query.deckIDs == nil
        let deckIDs = query.deckIDs ?? []
        let anyState = query.states == nil
        let stateRaws = (query.states ?? []).map(\.rawValue)
        let dueBefore = query.dueBefore ?? .distantFuture
        let anyNote = query.noteID == nil
        let noteID = query.noteID ?? UUID()

        var descriptor = FetchDescriptor<SDCard>(
            predicate: #Predicate {
                (anyDeck || deckIDs.contains($0.deckID))
                    && (anyState || stateRaws.contains($0.stateRaw))
                    && $0.due <= dueBefore
                    && (anyNote || $0.noteID == noteID)
            },
            sortBy: [SortDescriptor(\.due, order: .forward)]
        )

        // ponytail: the tag filter walks the owning note's `[String]` in memory —
        // SwiftData will not put `card.note.tags.contains(_:)` into the predicate, and
        // the alternative is a dedicated SDTag join entity. The ceiling is the size of
        // the pre-tag candidate set (a deck's cards, thousands at MVP scale); if that
        // ever hurts, denormalize tags onto SDCard or add SDTag.
        guard let tag = query.tag else {
            if let limit = query.limit { descriptor.fetchLimit = limit }
            return try modelContext.fetch(descriptor).map { $0.toDomain() }
        }

        var matches = try modelContext.fetch(descriptor)
            .filter { $0.note?.tags.contains(tag) == true }
        if let limit = query.limit { matches = Array(matches.prefix(limit)) }
        return matches.map { $0.toDomain() }
    }

    public func save(_ card: Card) throws {
        let stored: SDCard
        if let existing = try fetchCard(id: card.id) {
            existing.apply(card)
            stored = existing
        } else {
            stored = SDCard(card)
            modelContext.insert(stored)
        }
        // Wiring the note is what puts the card under the note's cascade. Callers save
        // the note first; if they did not, the card still persists with its noteID.
        if stored.note?.id != card.noteID {
            let noteID = card.noteID
            var descriptor = FetchDescriptor<SDNote>(predicate: #Predicate { $0.id == noteID })
            descriptor.fetchLimit = 1
            stored.note = try modelContext.fetch(descriptor).first
        }
        try modelContext.save()
    }

    public func delete(ids: [UUID]) throws {
        try modelContext.delete(model: SDCard.self, where: #Predicate { ids.contains($0.id) })
        try modelContext.save()
    }

    private func fetchCard(id: UUID) throws -> SDCard? {
        var descriptor = FetchDescriptor<SDCard>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
