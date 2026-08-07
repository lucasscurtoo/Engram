import Application
import Foundation

/// Read-only screen state over `StatsService`. The aggregation lives in the service;
/// this only tracks loading/error and hands the `Overview` to the charts.
@MainActor
@Observable
final class StatsViewModel {
    private(set) var overview: StatsService.Overview?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let statsService: StatsService

    init(statsService: StatsService) {
        self.statsService = statsService
    }

    /// True once anything has been studied. Cards alone are not history — an empty
    /// 30-day window of zeros is noise, not a chart.
    var hasHistory: Bool {
        guard let overview else { return false }
        return overview.reviewsPerDay.contains { $0.count > 0 } || overview.focusSessionsCompleted > 0
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            overview = try await statsService.overview(days: 30, now: .now)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
