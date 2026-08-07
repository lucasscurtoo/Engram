import Application
import Charts
import Domain
import SwiftUI

/// Stats dashboard: everything comes from `StatsService.Overview`, nothing is
/// recomputed here. Default chart styling only, so light/dark follow the system.
struct StatsView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var model: StatsViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .task {
            let model = model ?? StatsViewModel(statsService: dependencies.statsService)
            self.model = model
            await model.load()
        }
    }

    @ViewBuilder
    private func content(_ model: StatsViewModel) -> some View {
        Group {
            if let message = model.errorMessage {
                ContentUnavailableView(
                    "Stats unavailable", systemImage: "exclamationmark.triangle", description: Text(message)
                )
            } else if let overview = model.overview {
                if model.hasHistory {
                    ScrollView { OverviewCharts(overview: overview).padding() }
                } else {
                    ContentUnavailableView(
                        "Study a bit first…",
                        systemImage: "chart.bar",
                        description: Text("Your review and focus history will show up here.")
                    )
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Stats")
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.load() } }
                .disabled(model.isLoading)
        }
    }
}

private struct OverviewCharts: View {
    let overview: StatsService.Overview

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
                BigNumber(title: "Retention", value: Self.percent(overview.retention))
                BigNumber(title: "Due today", value: "\(overview.dueToday)")
                BigNumber(title: "Due next 7 days", value: "\(overview.dueNextSevenDays)")
            }

            ChartSection(title: "Reviews per day", subtitle: "Last 30 days") {
                Chart(overview.reviewsPerDay, id: \.day) { entry in
                    BarMark(
                        x: .value("Day", entry.day, unit: .day),
                        y: .value("Reviews", entry.count)
                    )
                }
            }

            if !cardsByState.isEmpty {
                ChartSection(title: "Cards by state", subtitle: nil) {
                    Chart(cardsByState, id: \.state) { entry in
                        SectorMark(
                            angle: .value("Cards", entry.count),
                            innerRadius: .ratio(0.6),
                            angularInset: 1
                        )
                        .foregroundStyle(by: .value("State", entry.state.displayName))
                    }
                }
            }

            ChartSection(
                title: "Focus minutes per day",
                subtitle: "Last 30 days · \(overview.focusSessionsCompleted) sessions completed"
            ) {
                Chart(overview.focusMinutesPerDay, id: \.day) { entry in
                    BarMark(
                        x: .value("Day", entry.day, unit: .day),
                        y: .value("Minutes", entry.count)
                    )
                }
            }
        }
    }

    /// Zero states are omitted — an empty slice is not information.
    private var cardsByState: [(state: CardState, count: Int)] {
        CardState.allCases.compactMap { state in
            guard let count = overview.cardsByState[state], count > 0 else { return nil }
            return (state, count)
        }
    }

    /// nil retention means "never graded a review card" — an em dash, not 0%.
    private static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct BigNumber: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.largeTitle, design: .rounded).weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ChartSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content.frame(height: 200)
        }
    }
}

private extension CardState {
    var displayName: String {
        switch self {
        case .new: "New"
        case .learning: "Learning"
        case .review: "Review"
        case .relearning: "Relearning"
        }
    }
}
