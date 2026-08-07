import Foundation
import Domain

/// Stats use cases (M6). Skeleton: signatures are the contract, bodies pending.
public actor StatsService {
    public struct DailyCount: Sendable, Hashable {
        public let day: Date
        public let count: Int
    }

    private let reviewLogRepository: any ReviewLogRepository
    private let cardRepository: any CardRepository

    public init(reviewLogRepository: any ReviewLogRepository, cardRepository: any CardRepository) {
        self.reviewLogRepository = reviewLogRepository
        self.cardRepository = cardRepository
    }

    // TODO(owner): M6 — implement from ReviewLog + CardQuery:
    // reviewsPerDay(last30Days:), cardCountsByState(), retention(period:),
    // dueForecast(days: 7), and focus minutes per day.
    // TODO(owner): M5 must define a FocusSessionLog entity + repository so focus
    // stats have a source of truth; add it next to ReviewLog.
}
