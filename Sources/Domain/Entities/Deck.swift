import Foundation

/// Per-deck scheduling configuration (seam 6): different domains forget differently.
public struct DeckConfig: Sendable, Codable, Hashable {
    public var requestRetention: Double
    public var newCardsPerDay: Int
    public var maxReviewsPerDay: Int

    public init(requestRetention: Double = 0.9, newCardsPerDay: Int = 20, maxReviewsPerDay: Int = 200) {
        self.requestRetention = requestRetention
        self.newCardsPerDay = newCardsPerDay
        self.maxReviewsPerDay = maxReviewsPerDay
    }
}

/// Decks are hierarchical via `parentID`; `name` is the leaf segment.
/// Full path renders as "Parent::Child" (see `DeckTree.fullName`).
public struct Deck: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var parentID: UUID?
    public var config: DeckConfig
    public var createdAt: Date

    public init(
        id: UUID = UUID(), name: String, parentID: UUID? = nil,
        config: DeckConfig = DeckConfig(), createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.config = config
        self.createdAt = createdAt
    }
}

/// Pure helpers over a flat deck list. Cycle-safe.
public enum DeckTree {
    /// `rootID` plus every transitive subdeck.
    public static func subtreeIDs(of rootID: UUID, in decks: [Deck]) -> Set<UUID> {
        let childrenByParent = Dictionary(grouping: decks.filter { $0.parentID != nil }) { $0.parentID! }
        var result: Set<UUID> = [rootID]
        var frontier = [rootID]
        while let current = frontier.popLast() {
            for child in childrenByParent[current] ?? [] where result.insert(child.id).inserted {
                frontier.append(child.id)
            }
        }
        return result
    }

    /// "Parent::Child" style full name.
    public static func fullName(of deckID: UUID, in decks: [Deck]) -> String {
        let byID = Dictionary(uniqueKeysWithValues: decks.map { ($0.id, $0) })
        var segments: [String] = []
        var visited: Set<UUID> = []
        var currentID: UUID? = deckID
        while let id = currentID, let deck = byID[id], visited.insert(id).inserted {
            segments.append(deck.name)
            currentID = deck.parentID
        }
        return segments.reversed().joined(separator: "::")
    }
}
