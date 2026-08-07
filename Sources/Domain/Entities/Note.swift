import Foundation

/// Content lives here, keyed by field name as declared in the owning `NoteType`.
/// A note generates one card per template of its note type (seam 1).
public struct Note: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public var noteTypeID: UUID
    public var deckID: UUID
    /// Field name -> raw content. No fixed front/back columns.
    public var fields: [String: String]
    /// Free-form tags (seam 4: flexible organization / future smart decks).
    public var tags: [String]
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(), noteTypeID: UUID, deckID: UUID,
        fields: [String: String], tags: [String] = [],
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
