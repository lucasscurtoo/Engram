import Domain
import Foundation
import SwiftData

@ModelActor
public actor SwiftDataReviewLogRepository: ReviewLogRepository {
    /// Append-only: logs are immutable, so no upsert path.
    public func append(_ log: ReviewLog) throws {
        modelContext.insert(SDReviewLog(log))
        try modelContext.save()
    }

    public func logs(from: Date, to: Date) throws -> [ReviewLog] {
        let descriptor = FetchDescriptor<SDReviewLog>(
            predicate: #Predicate { $0.reviewedAt >= from && $0.reviewedAt <= to },
            sortBy: [SortDescriptor(\.reviewedAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }
}
