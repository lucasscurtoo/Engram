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
            header
            Divider()
            content
        }
        // Fixed on purpose: a review sheet that resizes per card is worse than one
        // that scrolls, and the card body already scrolls (`StudyCardView`).
        .frame(width: 760, height: 560)
        .task { await model.start() }
    }

    private var header: some View {
        HStack {
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if model.item != nil {
                Text("\(model.progress.remaining) remaining · \(model.progress.completed) done")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            spread { ProgressView() }
        } else if let item = model.item {
            StudyCardView(model: model, item: item)
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
                Text(
                    """
                    \(model.progress.completed) cards reviewed · \
                    \(model.progress.correct) correct (\(model.correctPercentage)%) · \
                    \(model.elapsedMinutes) min
                    """
                )
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
