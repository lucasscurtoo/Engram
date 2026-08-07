// TODO(owner): M2 — SwiftData container factory.
// Contract:
//  - on-disk ModelContainer in the sandbox's Application Support directory
//  - versioned schema from day one: VersionedSchema (RecallSchemaV1) + SchemaMigrationPlan,
//    even while there is only v1 — avoids a destructive migration later
//  - registers SDDeck, SDNoteType, SDNote, SDCard, SDReviewLog
//  - seeds NoteType.basic (fixed UUID, idempotent) on first launch
