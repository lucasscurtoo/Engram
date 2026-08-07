import Domain
import SwiftUI

/// Set from anywhere in the view tree to open the review session; `ContentView`
/// owns the sheet. Avoids threading a callback through every entry point.
@MainActor
@Observable
final class StudyLauncher {
    var scope: StudyScope?
}

// ponytail: `.sheet(item:)` needs Identifiable and the scope is already Hashable.
extension StudyScope: @retroactive Identifiable {
    public var id: Self { self }
}

/// The review flow: the study card (`StudyCardView`, shared with focus mode) plus
/// this screen's own chrome — progress header, empty state and session summary.
struct ReviewSessionView: View {
    @State private var model: ReviewSessionViewModel
    @Environment(\.dismiss) private var dismiss

    init(scope: StudyScope, dependencies: AppDependencies) {
        _model = State(initialValue: ReviewSessionViewModel(
            scope: scope, session: dependencies.makeReviewSession()
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: fractionDone)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
            header
            content
        }
        // Fixed on purpose: a review sheet that resizes per card is worse than one
        // that scrolls, and the card body already scrolls (`StudyCardView`).
        .frame(width: 760, height: 560)
        .background(Theme.studyBackdrop)
        .task { await model.start() }
    }

    /// Share of the session's cards already graded — drives the top progress bar.
    private var fractionDone: Double {
        let total = model.progress.completed + model.progress.remaining
        return total == 0 ? 0 : Double(model.progress.completed) / Double(total)
    }

    private var header: some View {
        HStack {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Spacer()
            if model.errorMessage == nil, model.item != nil {
                Text("\(model.progress.remaining) remaining")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.space4)
        .padding(.vertical, Theme.space2)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            spread { ProgressView() }
        } else if let item = model.item {
            StudyCardView(model: model, item: item)
                .frame(maxWidth: 640)
                .padding(.horizontal, Theme.space5)
                .padding(.bottom, Theme.space5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isEmpty {
            spread {
                ContentUnavailableView(
                    "Nothing to review",
                    systemImage: "checkmark.circle",
                    description: Text("No cards are due here right now. Come back later.")
                )
            }
        } else {
            summary
        }
    }

    private var summary: some View {
        spread {
            ContentUnavailableView {
                Label("Session complete", systemImage: "checkmark.seal")
            } description: {
                HStack(spacing: Theme.space3) {
                    StatTile(title: "Reviewed", value: "\(model.progress.completed)")
                    StatTile(title: "Correct", value: "\(model.correctPercentage)%")
                    StatTile(title: "Minutes", value: "\(model.elapsedMinutes)")
                }
                .frame(maxWidth: 420)
                .padding(.top, Theme.space2)
            } actions: {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func spread<Body: View>(@ViewBuilder _ content: () -> Body) -> some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
