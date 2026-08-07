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

/// The review flow: front → "Show Answer" → back + the four ratings with their
/// preview intervals, then a session summary. Sides always come from
/// `noteType.frontFields/backFields`, never from a hardcoded note field.
///
/// Shortcuts are `.keyboardShortcut` on the buttons themselves: the buttons that
/// must not respond simply do not exist in that state (Show Answer is replaced by
/// the rating row on reveal), so no focus plumbing is needed for Space / 1-4 / Esc.
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
            card(item)
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

    private func card(_ item: StudyItem) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    fieldStack(fields(of: item, front: true))
                    if model.revealed {
                        Divider()
                        fieldStack(fields(of: item, front: false))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .frame(maxHeight: .infinity)
            Divider()
            controls
                .padding(12)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if model.revealed {
            HStack(spacing: 10) {
                ForEach(Rating.allCases, id: \.self) { rating in
                    Button {
                        Task { await model.grade(rating) }
                    } label: {
                        VStack(spacing: 2) {
                            Text(Self.title(of: rating))
                            Text(model.intervalLabel(for: rating))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue)")), modifiers: [])
                    .help("Press \(rating.rawValue)")
                }
            }
        } else {
            Button("Show Answer") { model.revealed = true }
                .keyboardShortcut(.space, modifiers: [])
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .help("Press Space")
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

    private func fieldStack(_ fields: [NoteType.RenderableField]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(fields.indices, id: \.self) { FieldContentView(fields[$0]) }
        }
        .font(.title3)
        .textSelection(.enabled)
    }

    /// Defensive: a note type edited after its cards were generated could leave
    /// `templateIndex` dangling, and `frontFields` would trap on it.
    private func fields(of item: StudyItem, front: Bool) -> [NoteType.RenderableField] {
        let index = item.card.templateIndex
        guard item.noteType.templates.indices.contains(index) else { return [] }
        return front
            ? item.noteType.frontFields(of: item.note, templateIndex: index)
            : item.noteType.backFields(of: item.note, templateIndex: index)
    }

    private func spread<Body: View>(@ViewBuilder _ content: () -> Body) -> some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func title(of rating: Rating) -> String {
        switch rating {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}
