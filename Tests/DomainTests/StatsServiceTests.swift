import Foundation
import Testing
import Domain
import Application

@Suite("StatsService")
struct StatsServiceTests {
    // Fixed UTC calendar so day boundaries are deterministic.
    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2025-01-10 12:00:00 UTC
    private let now = Date(timeIntervalSince1970: 1_736_510_400)
    private func daysAgo(_ days: Int, hour: TimeInterval = 0) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400 + hour)
    }

    private actor FakeFocusLogs: FocusSessionLogRepository {
        var stored: [FocusSessionLog] = []
        func seed(_ logs: [FocusSessionLog]) { stored = logs }
        func append(_ log: FocusSessionLog) { stored.append(log) }
        func logs(from: Date, to: Date) -> [FocusSessionLog] {
            stored.filter { $0.startedAt >= from && $0.startedAt <= to }.sorted { $0.startedAt < $1.startedAt }
        }
    }

    private func reviewLog(daysAgo days: Int, rating: Rating, stateBefore: CardState) -> ReviewLog {
        ReviewLog(
            cardID: UUID(), rating: rating, reviewedAt: daysAgo(days),
            scheduledDays: 1, elapsedDays: 1, stateBefore: stateBefore,
            stabilityAfter: 1, difficultyAfter: 5
        )
    }

    private func card(state: CardState, dueInDays: Double) -> Card {
        Card(
            id: UUID(), noteID: UUID(), templateIndex: 0, deckID: UUID(),
            state: state, step: nil, due: now.addingTimeInterval(dueInDays * 86_400),
            stability: 1, difficulty: 5, reps: 1, lapses: 0, lastReview: now, createdAt: now
        )
    }

    @Test func aggregatesReviewsRetentionDueAndFocus() async throws {
        let store = InMemoryStore()
        let focusLogs = FakeFocusLogs()
        let service = StatsService(
            reviewLogRepository: InMemoryReviewLogRepository(store: store),
            cardRepository: InMemoryCardRepository(store: store),
            focusLogRepository: focusLogs
        )

        // Reviews: 2 today, 1 two days ago. Retention basis: review-state grades
        // (good, again, good = 2/3); the learning-state grade must not count.
        for log in [
            reviewLog(daysAgo: 0, rating: .good, stateBefore: .review),
            reviewLog(daysAgo: 0, rating: .again, stateBefore: .review),
            reviewLog(daysAgo: 2, rating: .good, stateBefore: .review),
            reviewLog(daysAgo: 2, rating: .good, stateBefore: .learning),
        ] {
            await store.appendLog(log)
        }

        // Cards: overdue review, due-tomorrow review, due-in-10-days, new.
        await store.seed(cards: [
            card(state: .review, dueInDays: -1),
            card(state: .review, dueInDays: 1),
            card(state: .learning, dueInDays: 10),
            card(state: .new, dueInDays: 0),
        ])

        // Focus: 25 min yesterday, 50 min today.
        await focusLogs.seed([
            FocusSessionLog(
                startedAt: daysAgo(1), endedAt: daysAgo(1, hour: 1_500),
                focusedSeconds: 25 * 60, completedFocusBlocks: 1, cardsCompleted: 5
            ),
            FocusSessionLog(
                startedAt: daysAgo(0), endedAt: now,
                focusedSeconds: 50 * 60, completedFocusBlocks: 2, cardsCompleted: 20
            ),
        ])

        let overview = try await service.overview(days: 7, now: now, calendar: Self.utc)

        #expect(overview.reviewsPerDay.count == 7)
        #expect(overview.reviewsPerDay.map(\.count) == [0, 0, 0, 0, 2, 0, 2])
        #expect(overview.retention == 2.0 / 3.0)
        #expect(overview.cardsByState == [.review: 2, .learning: 1, .new: 1])
        #expect(overview.dueToday == 1)
        #expect(overview.dueNextSevenDays == 1)
        #expect(overview.focusMinutesPerDay.suffix(2).map(\.count) == [25, 50])
        #expect(overview.focusSessionsCompleted == 2)
    }

    @Test func emptyStoreYieldsZeroFilledDaysAndNilRetention() async throws {
        let store = InMemoryStore()
        let service = StatsService(
            reviewLogRepository: InMemoryReviewLogRepository(store: store),
            cardRepository: InMemoryCardRepository(store: store),
            focusLogRepository: FakeFocusLogs()
        )
        let overview = try await service.overview(days: 30, now: now, calendar: Self.utc)
        #expect(overview.reviewsPerDay.count == 30)
        #expect(overview.reviewsPerDay.allSatisfy { $0.count == 0 })
        #expect(overview.retention == nil)
        #expect(overview.cardsByState.isEmpty)
        #expect(overview.dueToday == 0)
    }
}
