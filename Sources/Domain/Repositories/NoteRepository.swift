import Foundation

/// Browser/search seam: text + tag filtering for the note browser (M3).
public struct NoteQuery: Sendable, Hashable {
    public var deckIDs: [UUID]?
    /// Case-insensitive substring match over all field values.
    public var text: String?
    public var tag: String?
    public var limit: Int?

    public init(deckIDs: [UUID]? = nil, text: String? = nil, tag: String? = nil, limit: Int? = nil) {
        self.deckIDs = deckIDs
        self.text = text
        self.tag = tag
        self.limit = limit
    }
}

public protocol NoteRepository: Sendable {
    func note(id: UUID) async throws -> Note?
    func notes(matching query: NoteQuery) async throws -> [Note]
    func save(_ note: Note) async throws
    /// Must cascade the note's cards (and their review logs stay — they are history).
    func delete(id: UUID) async throws
}

public protocol NoteTypeRepository: Sendable {
    func noteType(id: UUID) async throws -> NoteType?
    func allNoteTypes() async throws -> [NoteType]
    func save(_ noteType: NoteType) async throws
}
