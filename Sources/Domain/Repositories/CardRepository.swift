import Foundation

/// One query struct instead of N ad-hoc methods: this is also the smart-deck seam —
/// a saved filter is just a stored `CardQuery` (seam 4).
public struct CardQuery: Sendable, Hashable {
    /// nil = any deck. Callers resolve subdeck trees before querying (see `DeckTree`).
    public var deckIDs: [UUID]?
    /// Filters through the owning note's tags. nil = any.
    public var tag: String?
    public var states: Set<CardState>?
    public var dueBefore: Date?
    public var noteID: UUID?
    public var limit: Int?

    public init(
        deckIDs: [UUID]? = nil, tag: String? = nil, states: Set<CardState>? = nil,
        dueBefore: Date? = nil, noteID: UUID? = nil, limit: Int? = nil
    ) {
        self.deckIDs = deckIDs
        self.tag = tag
        self.states = states
        self.dueBefore = dueBefore
        self.noteID = noteID
        self.limit = limit
    }
}

public protocol CardRepository: Sendable {
    /// Results are sorted by `due` ascending (queue order). Implementations must honor this.
    func cards(matching query: CardQuery) async throws -> [Card]
    func save(_ card: Card) async throws
    func delete(ids: [UUID]) async throws
}
