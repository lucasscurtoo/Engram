import Domain
import SwiftUI

/// One card of the review flow: front → "Show Answer" → back + the four ratings with
/// their preview intervals. Sides always come from `noteType.frontFields/backFields`
/// and render through `FieldContentView` — never a hardcoded note field.
///
/// Extracted from `ReviewSessionView` (M4, behaviour unchanged) so focus mode can
/// embed the exact same study UI instead of duplicating it.
///
/// Shortcuts are `.keyboardShortcut` on the buttons themselves: the buttons that must
/// not respond simply do not exist in that state (Show Answer is replaced by the
/// rating row on reveal), so no focus plumbing is needed for Space / 1-4.
struct StudyCardView: View {
    let model: ReviewSessionViewModel
    let item: StudyItem
    /// Fires after every graded card — focus mode reports it to the focus engine.
    var onGraded: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    fieldStack(fields(front: true))
                    if model.revealed {
                        Divider()
                        fieldStack(fields(front: false))
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
                        Task {
                            await model.grade(rating)
                            onGraded()
                        }
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

    private func fieldStack(_ fields: [NoteType.RenderableField]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(fields.indices, id: \.self) { FieldContentView(fields[$0]) }
        }
        .font(.title3)
        .textSelection(.enabled)
    }

    /// Defensive: a note type edited after its cards were generated could leave
    /// `templateIndex` dangling, and `frontFields` would trap on it.
    private func fields(front: Bool) -> [NoteType.RenderableField] {
        let index = item.card.templateIndex
        guard item.noteType.templates.indices.contains(index) else { return [] }
        return front
            ? item.noteType.frontFields(of: item.note, templateIndex: index)
            : item.noteType.backFields(of: item.note, templateIndex: index)
    }

    static func title(of rating: Rating) -> String {
        switch rating {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}
