import Domain
import Foundation
import SwiftData

/// Schema v1. Versioned from day one so the first real migration is a `MigrationStage`
/// and not a destructive reset.
public enum RecallSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        // SDFocusSessionLog joined v1 pre-release (additive = lightweight migration).
        [SDDeck.self, SDNoteType.self, SDNote.self, SDCard.self, SDReviewLog.self, SDFocusSessionLog.self]
    }
}

public enum RecallMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [RecallSchemaV1.self] }
    /// Empty until v2 exists.
    public static var stages: [MigrationStage] { [] }
}

extension ModelContainer {
    /// On-disk store. `directory` defaults to `Application Support/Recall`;
    /// tests pass a temp directory so they never touch the user's library.
    public static func recall(directory: URL? = nil) throws -> ModelContainer {
        let directory = try directory ?? defaultStoreDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            schema: Schema(versionedSchema: RecallSchemaV1.self),
            url: directory.appendingPathComponent("Recall.store")
        )
        return try makeRecallContainer(configuration)
    }

    /// Ephemeral store for tests and previews.
    public static func recallInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: Schema(versionedSchema: RecallSchemaV1.self),
            isStoredInMemoryOnly: true
        )
        return try makeRecallContainer(configuration)
    }

    private static func makeRecallContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        let container = try ModelContainer(
            for: Schema(versionedSchema: RecallSchemaV1.self),
            migrationPlan: RecallMigrationPlan.self,
            configurations: configuration
        )
        try seedBuiltInNoteTypes(in: container)
        return container
    }

    /// Idempotent: `NoteType.basic` has a fixed UUID, so reopening an existing store
    /// finds it and does nothing.
    private static func seedBuiltInNoteTypes(in container: ModelContainer) throws {
        let context = ModelContext(container)
        let basic = NoteType.basic
        let basicID = basic.id
        var descriptor = FetchDescriptor<SDNoteType>(predicate: #Predicate { $0.id == basicID })
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }
        context.insert(try SDNoteType(basic))
        try context.save()
    }

    private static func defaultStoreDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("Recall", isDirectory: true)
    }
}
