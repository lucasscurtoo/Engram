import Foundation

/// Immutable record of one finished focus session — the source of truth for
/// focus stats (minutes per day, sessions completed, cards per session).
public struct FocusSessionLog: Identifiable, Sendable, Codable, Hashable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let focusedSeconds: TimeInterval
    public let completedFocusBlocks: Int
    public let cardsCompleted: Int

    public init(
        id: UUID = UUID(), startedAt: Date, endedAt: Date,
        focusedSeconds: TimeInterval, completedFocusBlocks: Int, cardsCompleted: Int
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.focusedSeconds = focusedSeconds
        self.completedFocusBlocks = completedFocusBlocks
        self.cardsCompleted = cardsCompleted
    }
}
