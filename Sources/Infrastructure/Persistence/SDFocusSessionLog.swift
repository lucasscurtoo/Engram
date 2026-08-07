import Domain
import Foundation
import SwiftData

/// Immutable focus-session history row. Standalone like `SDReviewLog` — never
/// touched by deck/note cascades.
@Model
public final class SDFocusSessionLog {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date
    public var focusedSeconds: TimeInterval
    public var completedFocusBlocks: Int
    public var cardsCompleted: Int

    public init(_ log: FocusSessionLog) {
        id = log.id
        startedAt = log.startedAt
        endedAt = log.endedAt
        focusedSeconds = log.focusedSeconds
        completedFocusBlocks = log.completedFocusBlocks
        cardsCompleted = log.cardsCompleted
    }

    public func toDomain() -> FocusSessionLog {
        FocusSessionLog(
            id: id, startedAt: startedAt, endedAt: endedAt,
            focusedSeconds: focusedSeconds,
            completedFocusBlocks: completedFocusBlocks,
            cardsCompleted: cardsCompleted
        )
    }
}

@ModelActor
public actor SwiftDataFocusSessionLogRepository: FocusSessionLogRepository {
    public func append(_ log: FocusSessionLog) throws {
        modelContext.insert(SDFocusSessionLog(log))
        try modelContext.save()
    }

    public func logs(from: Date, to: Date) throws -> [FocusSessionLog] {
        let descriptor = FetchDescriptor<SDFocusSessionLog>(
            predicate: #Predicate { $0.startedAt >= from && $0.startedAt <= to },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map { $0.toDomain() }
    }
}
