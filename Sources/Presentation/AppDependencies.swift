import Application
import Domain
import Foundation
import Infrastructure
import SwiftData

/// Composition root: one on-disk `ModelContainer` for the whole app, one repository
/// per aggregate on top of it, and the `DeckService` that every write goes through.
/// Built once in `RecallApp` and handed to the view tree via `.environment`.
@MainActor
@Observable
final class AppDependencies {
    let modelContainer: ModelContainer
    let deckRepository: SwiftDataDeckRepository
    let cardRepository: SwiftDataCardRepository
    let noteRepository: SwiftDataNoteRepository
    let noteTypeRepository: SwiftDataNoteTypeRepository
    let reviewLogRepository: SwiftDataReviewLogRepository
    let focusLogRepository: SwiftDataFocusSessionLogRepository
    let deckService: DeckService
    /// M5: the only distraction blocker in the app. Nothing but the focus engine
    /// calls it — the UI never activates/deactivates it directly.
    let focusBlocker = SystemFocusBlocker()

    /// One focus session for the whole app: the main window and the menu bar scene
    /// observe this instance. Lazy so it is only built when focus is first used.
    @ObservationIgnored private(set) lazy var focus = FocusSessionViewModel(dependencies: self)

    init() throws {
        let container = try ModelContainer.recall()
        modelContainer = container
        deckRepository = SwiftDataDeckRepository(modelContainer: container)
        cardRepository = SwiftDataCardRepository(modelContainer: container)
        noteRepository = SwiftDataNoteRepository(modelContainer: container)
        noteTypeRepository = SwiftDataNoteTypeRepository(modelContainer: container)
        reviewLogRepository = SwiftDataReviewLogRepository(modelContainer: container)
        focusLogRepository = SwiftDataFocusSessionLogRepository(modelContainer: container)
        deckService = DeckService(
            deckRepository: deckRepository,
            cardRepository: cardRepository,
            noteRepository: noteRepository
        )
    }

    /// One fresh session per study run — `ReviewSessionService` holds the queue state.
    func makeReviewSession() -> ReviewSessionService {
        ReviewSessionService(
            deckRepository: deckRepository,
            cardRepository: cardRepository,
            noteRepository: noteRepository,
            noteTypeRepository: noteTypeRepository,
            reviewLogRepository: reviewLogRepository
        )
    }

    /// Note types available to the editor. MVP seeds only "Basic", but nothing in the
    /// UI may assume that — falls back to the built-in type if the store is empty.
    func availableNoteTypes() async -> [NoteType] {
        let stored = (try? await noteTypeRepository.allNoteTypes()) ?? []
        return stored.isEmpty ? [.basic] : stored.sorted { $0.name < $1.name }
    }
}
