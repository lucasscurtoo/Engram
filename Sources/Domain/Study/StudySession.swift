import Foundation

/// What to study. `.deck` includes its subdecks.
public enum StudyScope: Sendable, Hashable {
    case deck(UUID)
    case all
    case tag(String)
    // TODO(owner): smart decks = saved CardQuery filters plug in here (seam 4).
}

/// Everything the UI needs to render one card: scheduling state + content + template.
public struct StudyItem: Sendable, Hashable {
    public let card: Card
    public let note: Note
    public let noteType: NoteType

    public init(card: Card, note: Note, noteType: NoteType) {
        self.card = card
        self.note = note
        self.noteType = noteType
    }
}

public struct StudyProgress: Sendable, Hashable {
    public var completed: Int
    /// Ratings other than `.again`.
    public var correct: Int
    public var remaining: Int

    public init(completed: Int = 0, correct: Int = 0, remaining: Int = 0) {
        self.completed = completed
        self.correct = correct
        self.remaining = remaining
    }
}

/// Seam 3: SRS review is ONE study mode. Cram/quiz/failed-only implement this
/// same protocol later without touching the review UI.
public protocol StudySession: Actor {
    var currentItem: StudyItem? { get }
    var progress: StudyProgress { get }
    /// Intervals to preview on the four answer buttons for the current item.
    func previewIntervals(now: Date) -> [Rating: TimeInterval]
    func grade(_ rating: Rating, now: Date) async throws
}
