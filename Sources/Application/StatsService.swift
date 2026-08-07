import Foundation
import Domain

/// Stats aggregations (M6). Pure queries over the immutable logs + current cards;
/// the UI renders `Overview` with Swift Charts and adds nothing on top.
public actor StatsService {
    public struct DailyCount: Sendable, Hashable {
        public let day: Date // start of day
        public let count: Int

        public init(day: Date, count: Int) {
            self.day = day
            self.count = count
        }
    }

    public struct Overview: Sendable, Hashable {
        /// One entry per day, oldest first, zero-filled.
        public let reviewsPerDay: [DailyCount]
        public let cardsByState: [CardState: Int]
        /// Share of non-Again ratings on `.review`-state cards in the period.
        /// nil when no review-state card was graded (no data ≠ 0%).
        public let retention: Double?
        /// Due now or earlier today (overdue included; `.new` excluded).
        public let dueToday: Int
        /// Due within the 7 days after today.
        public let dueNextSevenDays: Int
        /// One entry per day, oldest first, zero-filled.
        public let focusMinutesPerDay: [DailyCount]
        public let focusSessionsCompleted: Int
    }

    private let reviewLogRepository: any ReviewLogRepository
    private let cardRepository: any CardRepository
    private let focusLogRepository: any FocusSessionLogRepository

    public init(
        reviewLogRepository: any ReviewLogRepository,
        cardRepository: any CardRepository,
        focusLogRepository: any FocusSessionLogRepository
    ) {
        self.reviewLogRepository = reviewLogRepository
        self.cardRepository = cardRepository
        self.focusLogRepository = focusLogRepository
    }

    public func overview(
        days: Int = 30, now: Date, calendar: Calendar = .current
    ) async throws -> Overview {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        let dayStarts = (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: windowStart) }

        let reviews = try await reviewLogRepository.logs(from: windowStart, to: now)
        let reviewsByDay = Dictionary(grouping: reviews) { calendar.startOfDay(for: $0.reviewedAt) }
        let reviewsPerDay = dayStarts.map { DailyCount(day: $0, count: reviewsByDay[$0]?.count ?? 0) }

        let graded = reviews.filter { $0.stateBefore == .review }
        let retention = graded.isEmpty
            ? nil
            : Double(graded.count(where: { $0.rating != .again })) / Double(graded.count)

        let cards = try await cardRepository.cards(matching: CardQuery())
        let cardsByState = cards.reduce(into: [CardState: Int]()) { $0[$1.state, default: 0] += 1 }

        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: endOfToday) ?? endOfToday
        let scheduled = cards.filter { $0.state != .new }
        let dueToday = scheduled.count { $0.due < endOfToday }
        let dueNextSevenDays = scheduled.count { $0.due >= endOfToday && $0.due < weekEnd }

        let focusLogs = try await focusLogRepository.logs(from: windowStart, to: now)
        // ponytail: a session crossing midnight is attributed to its start day; split
        // it across days if that ever matters.
        let focusByDay = Dictionary(grouping: focusLogs) { calendar.startOfDay(for: $0.startedAt) }
        let focusMinutesPerDay = dayStarts.map { day in
            DailyCount(
                day: day,
                count: Int(((focusByDay[day] ?? []).reduce(0) { $0 + $1.focusedSeconds } / 60).rounded())
            )
        }

        return Overview(
            reviewsPerDay: reviewsPerDay,
            cardsByState: cardsByState,
            retention: retention,
            dueToday: dueToday,
            dueNextSevenDays: dueNextSevenDays,
            focusMinutesPerDay: focusMinutesPerDay,
            focusSessionsCompleted: focusLogs.count
        )
    }
}
