import Domain
import SwiftUI

/// How to study a scope. Seam 3 in the UI: one screen, one view model, two actors.
enum StudyMode: Hashable {
    /// FSRS-scheduled review of what is due.
    case review
    /// Shuffled practice over everything in scope; nothing is written.
    case cram
}

/// Set from anywhere in the view tree to open the study session; `ContentView`
/// owns the sheet. Avoids threading a callback through every entry point.
@MainActor
@Observable
final class StudyLauncher {
    /// ponytail: `.sheet(item:)` needs Identifiable and the pair is already Hashable.
    struct Request: Identifiable, Hashable {
        let scope: StudyScope
        var mode: StudyMode = .review
        var id: Self { self }
    }

    var request: Request?

    func study(_ scope: StudyScope, mode: StudyMode = .review) {
        request = Request(scope: scope, mode: mode)
    }
}

/// The review flow: the study card (`StudyCardView`, shared with focus mode) plus
/// this screen's own chrome — progress header, empty state and session summary.
///
/// Airy screen: edge-to-edge bg0 with one floating panel. Grading is keyboard-driven
/// and constant, so card-to-card is a 120 ms crossfade and nothing more.
struct ReviewSessionView: View {
    private let mode: StudyMode
    @State private var model: ReviewSessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(request: StudyLauncher.Request, dependencies: AppDependencies) {
        mode = request.mode
        let session: any StudySession = switch request.mode {
        case .review: dependencies.makeReviewSession()
        case .cram: dependencies.makeCramSession()
        }
        _model = State(initialValue: ReviewSessionViewModel(scope: request.scope, session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: fractionDone)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
            header
            content
        }
        .uiZoom()
        // Fixed on purpose: a review sheet that resizes per card is worse than one
        // that scrolls, and the card body already scrolls (`StudyCardView`).
        .frame(width: 760, height: 560)
        .background(Theme.bg0)
        .task { await model.start() }
    }

    /// Share of the session's cards already graded — drives the top progress bar.
    private var fractionDone: Double {
        let total = model.progress.completed + model.progress.remaining
        return total == 0 ? 0 : Double(model.progress.completed) / Double(total)
    }

    private var header: some View {
        HStack {
            if mode == .cram {
                // Quiet, but never absent: FSRS is off and the user must know it.
                Text("Practice").sectionCaps()
                    .help("Nothing here changes the schedule")
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(Theme.color(for: .again))
                    .lineLimit(1)
            }
            Spacer()
            if model.errorMessage == nil, model.item != nil {
                Text("\(model.progress.remaining) remaining")
                    .font(Theme.mono(.subheadline))
                    .foregroundStyle(Theme.textSecondary)
            }
            // Present only when there is something to take back — which is also what
            // scopes ⌘Z to the states where it means anything.
            if model.canUndo {
                Button("Undo") { Task { await model.undo() } }
                    .buttonStyle(.quiet)
                    .keyboardShortcut("z", modifiers: [.command])
                    .help("Undo the last rating (⌘Z)")
                    .accessibilityLabel("Undo last rating")
            }
            Button("Close") { dismiss() }
                .buttonStyle(.quiet)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, Theme.space4)
        .padding(.vertical, Theme.space3)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if model.isLoading {
                spread { ProgressView() }
            } else if let item = model.item {
                StudyCardView(model: model, item: item)
                    .frame(maxWidth: 640)
                    .padding(.horizontal, Theme.space5)
                    .padding(.bottom, Theme.space5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // A new card is a new view; the crossfade below does the rest.
                    .id(item.card.id)
                    .transition(.opacity)
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
        .animation(
            reduceMotion ? nil : .easeOut(duration: Theme.quick), value: model.item?.card.id
        )
    }

    private var summary: some View {
        spread {
            ContentUnavailableView {
                Label(
                    mode == .cram ? "Practice complete" : "Session complete",
                    systemImage: "checkmark.seal"
                )
            } description: {
                HStack(spacing: Theme.space3) {
                    StatTile(title: "Reviewed", value: "\(model.progress.completed)")
                    StatTile(title: "Correct", value: "\(model.correctPercentage)%")
                    StatTile(title: "Minutes", value: "\(model.elapsedMinutes)")
                }
                .frame(maxWidth: 460)
                .padding(.top, Theme.space3)
            } actions: {
                Button("Done") { dismiss() }
                    .buttonStyle(.accentAction)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func spread<Body: View>(@ViewBuilder _ content: () -> Body) -> some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
