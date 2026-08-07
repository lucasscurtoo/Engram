import Foundation

public protocol ReviewLogRepository: Sendable {
    func append(_ log: ReviewLog) async throws
    /// Stats seam (M6): logs within a date range, sorted by `reviewedAt` ascending.
    func logs(from: Date, to: Date) async throws -> [ReviewLog]
}
