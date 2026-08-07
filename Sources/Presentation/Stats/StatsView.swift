import Application
import Charts
import Domain
import SwiftUI

/// Stats dashboard: everything comes from `StatsService.Overview`, nothing is
/// recomputed here.
///
/// Dense screen: a 3-across tile row over hairlined chart panels. Every number is
/// monospaced, every gridline is a hairline, and the donut borrows the rating
/// palette so a "learning" slice is the same amber as the Hard button.
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg0)
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
                    ScrollView {
                        OverviewCharts(overview: overview)
                            .padding(Theme.space5)
                            .contentColumn()
                    }
                } else {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "chart.bar.xaxis",
                        description: Text("Study a few cards and your progress will show up here.")
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
        VStack(alignment: .leading, spacing: Theme.space4) {
            HStack(spacing: Theme.space3) {
                StatTile(title: "Retention", value: Self.percent(overview.retention))
                StatTile(title: "Due today", value: "\(overview.dueToday)")
                StatTile(title: "Due next 7 days", value: "\(overview.dueNextSevenDays)")
            }

            ChartSection(title: "Reviews per day", subtitle: "Last 30 days") {
                Chart(overview.reviewsPerDay, id: \.day) { entry in
                    BarMark(
                        x: .value("Day", entry.day, unit: .day),
                        y: .value("Reviews", entry.count)
                    )
                    .foregroundStyle(Theme.accent.gradient)
                }
                .technicalAxes()
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
                    .chartForegroundStyleScale(
                        domain: cardsByState.map(\.state.displayName),
                        range: cardsByState.map { Theme.color(for: $0.state) }
                    )
                    .chartLegend(position: .trailing, alignment: .center)
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
                    // Quieter than the review bars so the two charts read as a pair
                    // without competing.
                    .foregroundStyle(Theme.accent.opacity(0.6).gradient)
                }
                .technicalAxes()
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

private extension View {
    /// Hairline gridlines, monospaced tertiary labels, no tick marks: the chart body
    /// should be the only thing with weight.
    func technicalAxes() -> some View {
        chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel()
                    .font(Theme.mono(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel()
                    .font(Theme.mono(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

private struct ChartSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            Text(title).sectionCaps()
            if let subtitle {
                Text(subtitle)
                    .font(Theme.mono(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
            }
            content.frame(height: 200).padding(.top, Theme.space1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.space4)
        .panel(radius: Theme.Radius.tile)
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
