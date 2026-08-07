// TODO(owner): M2 — @Model classes mirroring the domain entities. One class per
// entity (split into SDDeck.swift / SDNote.swift / SDCard.swift / SDNoteType.swift /
// SDReviewLog.swift when written). Domain stays SwiftData-free; map via Mappers.swift.
//
// Contract (relationships per brief §7):
//  - SDDeck: self-relation parent/children (subdecks), 1-N SDNote, config fields inline
//  - SDNoteType: fields + templates encoded (Codable blobs are fine for MVP)
//  - SDNote: 1-N SDCard, fields dict + tags stored *queryably* (tags must be
//    filterable — dedicated SDTag entity or indexable array, so tag search works)
//  - SDCard: full FSRS state incl. `step`; denormalized deckID for queue queries;
//    1-N SDReviewLog
//  - SDReviewLog: immutable, never deleted when a card/note is deleted (history)
//
// Repositories to implement here (conforming to the Domain protocols):
//  - SwiftDataDeckRepository (delete cascades subdecks/notes/cards)
//  - SwiftDataCardRepository (honors CardQuery incl. tag-through-note; sorted by due)
//  - SwiftDataNoteRepository + SwiftDataNoteTypeRepository
//  - SwiftDataReviewLogRepository
// Acceptance (M2): integration test that creates deck+cards, saves, reopens the
// container, reads them back.
