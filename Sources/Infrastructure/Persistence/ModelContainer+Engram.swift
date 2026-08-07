import Domain
import Foundation
import SwiftData

/// Schema v1. Versioned from day one so the first real migration is a `MigrationStage`
/// and not a destructive reset.
public enum EngramSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        // SDFocusSessionLog joined v1 pre-release (additive = lightweight migration).
        [SDDeck.self, SDNoteType.self, SDNote.self, SDCard.self, SDReviewLog.self, SDFocusSessionLog.self]
    }
}

public enum EngramMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [EngramSchemaV1.self] }
    /// Empty until v2 exists.
    public static var stages: [MigrationStage] { [] }
}

extension ModelContainer {
    /// On-disk store. `directory` defaults to `Application Support/Engram`;
    /// tests pass a temp directory so they never touch the user's library.
    public static func engram(directory: URL? = nil) throws -> ModelContainer {
        let directory = try directory ?? defaultStoreDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            schema: Schema(versionedSchema: EngramSchemaV1.self),
            url: directory.appendingPathComponent("Engram.store")
        )
        return try makeEngramContainer(configuration)
    }

    /// Ephemeral store for tests and previews.
    public static func engramInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: Schema(versionedSchema: EngramSchemaV1.self),
            isStoredInMemoryOnly: true
        )
        return try makeEngramContainer(configuration)
    }

    private static func makeEngramContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        let container = try ModelContainer(
            for: Schema(versionedSchema: EngramSchemaV1.self),
            migrationPlan: EngramMigrationPlan.self,
            configurations: configuration
        )
        try seedBuiltInNoteTypes(in: container)
        return container
    }

    /// Idempotent: built-in note types have fixed UUIDs, so reopening an existing
    /// store finds them and does nothing. New built-ins seed on next launch.
    private static func seedBuiltInNoteTypes(in container: ModelContainer) throws {
        let context = ModelContext(container)
        var inserted = false
        for noteType in NoteType.builtIns {
            let typeID = noteType.id
            var descriptor = FetchDescriptor<SDNoteType>(predicate: #Predicate { $0.id == typeID })
            descriptor.fetchLimit = 1
            guard try context.fetch(descriptor).isEmpty else { continue }
            context.insert(try SDNoteType(noteType))
            inserted = true
        }
        if inserted { try context.save() }
    }

    private static func defaultStoreDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("Engram", isDirectory: true)
    }
}
