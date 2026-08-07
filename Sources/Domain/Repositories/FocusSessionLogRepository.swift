import Foundation

public protocol FocusSessionLogRepository: Sendable {
    func append(_ log: FocusSessionLog) async throws
    /// Sessions overlapping the range by `startedAt`, ascending.
    func logs(from: Date, to: Date) async throws -> [FocusSessionLog]
}
