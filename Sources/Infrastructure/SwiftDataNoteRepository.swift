import Domain
import Foundation
import SwiftData

@ModelActor
public actor SwiftDataNoteRepository: NoteRepository {
    public func note(id: UUID) throws -> Note? {
        try fetchNote(id: id)?.toDomain()
    }

    public func notes(matching query: NoteQuery) throws -> [Note] {
        let anyDeck = query.deckIDs == nil
        let deckIDs = query.deckIDs ?? []
        let descriptor = FetchDescriptor<SDNote>(
            predicate: #Predicate { anyDeck || deckIDs.contains($0.deckID) }
        )

        // ponytail: tag and text filtering run in memory. Neither `[String].contains`
        // nor a `[String: String]` value scan survives translation to a SwiftData
        // predicate. Ceiling is one deck's notes per query; if the browser gets slow,
        // the fix is an FTS-ish denormalized `searchText` column on SDNote, not a
        // cleverer predicate.
        var matches = try modelContext.fetch(descriptor).filter { note in
            if let tag = query.tag, !note.tags.contains(tag) { return false }
            if let text = query.text,
               !note.fields.values.contains(where: { $0.localizedCaseInsensitiveContains(text) }) {
                return false
            }
            return true
        }
        if let limit = query.limit { matches = Array(matches.prefix(limit)) }
        return matches.map { $0.toDomain() }
    }

    public func save(_ note: Note) throws {
        let stored: SDNote
        if let existing = try fetchNote(id: note.id) {
            existing.apply(note)
            stored = existing
        } else {
            stored = SDNote(note)
            modelContext.insert(stored)
        }
        if stored.deck?.id != note.deckID {
            let deckID = note.deckID
            var descriptor = FetchDescriptor<SDDeck>(predicate: #Predicate { $0.id == deckID })
            descriptor.fetchLimit = 1
            stored.deck = try modelContext.fetch(descriptor).first
        }
        try modelContext.save()
    }

    /// Cascades into the note's cards. Review logs are standalone and stay.
    public func delete(id: UUID) throws {
        guard let stored = try fetchNote(id: id) else { return }
        modelContext.delete(stored)
        try modelContext.save()
    }

    private func fetchNote(id: UUID) throws -> SDNote? {
        var descriptor = FetchDescriptor<SDNote>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}

@ModelActor
public actor SwiftDataNoteTypeRepository: NoteTypeRepository {
    public func noteType(id: UUID) throws -> NoteType? {
        try fetchNoteType(id: id)?.toDomain()
    }

    public func allNoteTypes() throws -> [NoteType] {
        try modelContext.fetch(FetchDescriptor<SDNoteType>()).map { try $0.toDomain() }
    }

    public func save(_ noteType: NoteType) throws {
        if let existing = try fetchNoteType(id: noteType.id) {
            try existing.apply(noteType)
        } else {
            modelContext.insert(try SDNoteType(noteType))
        }
        try modelContext.save()
    }

    private func fetchNoteType(id: UUID) throws -> SDNoteType? {
        var descriptor = FetchDescriptor<SDNoteType>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
