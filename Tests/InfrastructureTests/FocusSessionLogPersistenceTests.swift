import Foundation
import SwiftData
import Testing
import Domain
import Infrastructure

@Suite("SwiftDataFocusSessionLogRepository")
struct FocusSessionLogPersistenceTests {
    @Test func roundTripsAndFiltersByRange() async throws {
        let container = try ModelContainer.engramInMemory()
        let repository = SwiftDataFocusSessionLogRepository(modelContainer: container)
        let base = Date(timeIntervalSince1970: 1_735_732_800)

        let inRange = FocusSessionLog(
            startedAt: base, endedAt: base.addingTimeInterval(1_500),
            focusedSeconds: 1_500, completedFocusBlocks: 1, cardsCompleted: 12
        )
        let outOfRange = FocusSessionLog(
            startedAt: base.addingTimeInterval(-86_400), endedAt: base.addingTimeInterval(-80_000),
            focusedSeconds: 600, completedFocusBlocks: 0, cardsCompleted: 0
        )
        try await repository.append(inRange)
        try await repository.append(outOfRange)

        let fetched = try await repository.logs(from: base, to: base.addingTimeInterval(3_600))
        #expect(fetched == [inRange])
    }
}
