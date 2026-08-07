import Foundation
import Domain

/// The SRS study mode (M4 core). Builds the day's queue and applies FSRS on grading.
public actor ReviewSessionService: StudySession {
    /// Seam 6: the scheduler is rebuilt per session from the scoped deck's config,
    /// so requestRetention is per-deck. `.all`/`.tag` sessions use the default config.
    private let makeScheduler: @Sendable (DeckConfig) -> any Scheduler
    private var scheduler: any Scheduler
    private let deckRepository: any DeckRepository
    private let cardRepository: any CardRepository
    private let noteRepository: any NoteRepository
    private let noteTypeRepository: any NoteTypeRepository
    private let reviewLogRepository: any ReviewLogRepository

    private var queue: [StudyItem] = []
    private var completed = 0
    private var correct = 0

    public init(
        makeScheduler: @escaping @Sendable (DeckConfig) -> any Scheduler = {
            FSRS(parameters: FSRSParameters(deckConfig: $0))
        },
        deckRepository: any DeckRepository,
        cardRepository: any CardRepository,
        noteRepository: any NoteRepository,
        noteTypeRepository: any NoteTypeRepository,
        reviewLogRepository: any ReviewLogRepository
    ) {
        self.makeScheduler = makeScheduler
        self.scheduler = makeScheduler(DeckConfig())
        self.deckRepository = deckRepository
        self.cardRepository = cardRepository
        self.noteRepository = noteRepository
        self.noteTypeRepository = noteTypeRepository
        self.reviewLogRepository = reviewLogRepository
    }

    public var currentItem: StudyItem? { queue.first }

    public var progress: StudyProgress {
        StudyProgress(completed: completed, correct: correct, remaining: queue.count)
    }

    /// Builds the queue: due cards first (oldest due first), then new cards up to the daily limit.
    /// TODO(owner): subtract cards already studied today from the daily limits (needs today's logs).
    public func start(scope: StudyScope, now: Date) async throws {
        completed = 0
        correct = 0
        let (deckIDs, tag, config) = try await resolve(scope: scope)
        scheduler = makeScheduler(config)
        let due = try await cardRepository.cards(matching: CardQuery(
            deckIDs: deckIDs, tag: tag,
            states: [.learning, .review, .relearning],
            dueBefore: now,
            limit: config.maxReviewsPerDay
        ))
        let fresh = try await cardRepository.cards(matching: CardQuery(
            deckIDs: deckIDs, tag: tag,
            states: [.new],
            limit: config.newCardsPerDay
        ))
        queue = try await items(for: due + fresh)
    }

    public func previewIntervals(now: Date) -> [Rating: TimeInterval] {
        guard let item = currentItem else { return [:] }
        return scheduler.schedule(card: item.card, now: now).mapValues(\.interval)
    }

    /// Applies FSRS, persists card + review log, advances the queue.
    /// Cards still inside a learning/relearning step re-enter at the back of the session.
    public func grade(_ rating: Rating, now: Date) async throws {
        guard let item = currentItem,
              let info = scheduler.schedule(card: item.card, now: now)[rating] else { return }
        queue.removeFirst()

        try await cardRepository.save(info.card)
        try await reviewLogRepository.append(ReviewLog(
            cardID: item.card.id,
            rating: rating,
            reviewedAt: now,
            scheduledDays: Int(info.interval / 86_400),
            elapsedDays: item.card.lastReview.map { max(0, Int(now.timeIntervalSince($0) / 86_400)) } ?? 0,
            stateBefore: item.card.state,
            stabilityAfter: info.card.stability,
            difficultyAfter: info.card.difficulty
        ))

        completed += 1
        if rating != .again { correct += 1 }
        if info.card.state == .learning || info.card.state == .relearning {
            queue.append(StudyItem(card: info.card, note: item.note, noteType: item.noteType))
        }
    }

    // MARK: - Private

    private func resolve(scope: StudyScope) async throws -> ([UUID]?, String?, DeckConfig) {
        switch scope {
        case .all:
            return (nil, nil, DeckConfig())
        case .tag(let tag):
            return (nil, tag, DeckConfig())
        case .deck(let id):
            let decks = try await deckRepository.allDecks()
            let config = decks.first { $0.id == id }?.config ?? DeckConfig()
            return (Array(DeckTree.subtreeIDs(of: id, in: decks)), nil, config)
        }
    }

    private func items(for cards: [Card]) async throws -> [StudyItem] {
        var noteCache: [UUID: Note] = [:]
        var typeCache: [UUID: NoteType] = [:]
        var result: [StudyItem] = []
        for card in cards {
            guard let note = try await cached(card.noteID, in: &noteCache, fetch: noteRepository.note),
                  let type = try await cached(note.noteTypeID, in: &typeCache, fetch: noteTypeRepository.noteType)
            else { continue } // orphan card — skip defensively
            result.append(StudyItem(card: card, note: note, noteType: type))
        }
        return result
    }

    private func cached<T>(
        _ id: UUID, in cache: inout [UUID: T], fetch: (UUID) async throws -> T?
    ) async throws -> T? {
        if let hit = cache[id] { return hit }
        guard let fetched = try await fetch(id) else { return nil }
        cache[id] = fetched
        return fetched
    }
}
