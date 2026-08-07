import Application
import Domain
import Foundation
import Infrastructure
import SwiftData

/// Composition root: one on-disk `ModelContainer` for the whole app, one repository
/// per aggregate on top of it, and the `DeckService` that every write goes through.
/// Built once in `EngramApp` and handed to the view tree via `.environment`.
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
    let statsService: StatsService
    /// M7: the app's only error surface. Shared by every scene so a failure raised
    /// from Quick Add is the same object the main window would have shown.
    let errors = ErrorReporter()
    /// M6: owns the one pending daily reminder. Settings is its only caller.
    let reviewNotificationScheduler = ReviewNotificationScheduler()
    /// M5: the only distraction blocker in the app. Nothing but the focus engine
    /// calls it — the UI never activates/deactivates it directly.
    let focusBlocker = SystemFocusBlocker()

    /// One focus session for the whole app: the main window and the menu bar scene
    /// observe this instance. Lazy so it is only built when focus is first used.
    @ObservationIgnored private(set) lazy var focus = FocusSessionViewModel(dependencies: self)

    init() throws {
        let container = try ModelContainer.engram()
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
            noteRepository: noteRepository,
            noteTypeRepository: noteTypeRepository
        )
        statsService = StatsService(
            reviewLogRepository: reviewLogRepository,
            cardRepository: cardRepository,
            focusLogRepository: focusLogRepository
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

    /// Same repositories, no scheduler and no logs: cram writes nothing.
    func makeCramSession() -> CramSession {
        CramSession(
            deckRepository: deckRepository,
            cardRepository: cardRepository,
            noteRepository: noteRepository,
            noteTypeRepository: noteTypeRepository
        )
    }

    /// Note types available to the editor. MVP seeds only "Basic", but nothing in the
    /// UI may assume that — falls back to the built-in type if the store is empty.
    /// A *failed* read is reported; an empty store is not an error.
    func availableNoteTypes() async -> [NoteType] {
        let stored = await errors.value({ try await noteTypeRepository.allNoteTypes() }, fallback: [])
        return stored.isEmpty ? [.basic] : stored.sorted { $0.name < $1.name }
    }
}
