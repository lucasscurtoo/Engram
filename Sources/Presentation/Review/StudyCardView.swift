import Domain
import SwiftUI

/// One card of the review flow: front → "Show Answer" → back + the four ratings with
/// their preview intervals. Sides always come from `noteType.frontFields/backFields`
/// and render through `FieldContentView` — never a hardcoded note field.
///
/// Extracted from `ReviewSessionView` (M4, behaviour unchanged) so focus mode can
/// embed the exact same study UI instead of duplicating it.
///
/// The view carries its own `.cardSurface()` so the review sheet and the focus screen
/// get the identical card without either of them restating the elevation.
///
/// Shortcuts are `.keyboardShortcut` on the buttons themselves: the buttons that must
/// not respond simply do not exist in that state (Show Answer is replaced by the
/// rating row on reveal), so no focus plumbing is needed for Space / 1-4.
struct StudyCardView: View {
    let model: ReviewSessionViewModel
    let item: StudyItem
    /// Fires after every graded card — focus mode reports it to the focus engine.
    var onGraded: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.space5) {
            // Short cards sit vertically centered (Mochi); long ones grow and scroll.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: Theme.space5) {
                        fieldStack(fields(front: true))
                        if model.revealed {
                            VStack(spacing: Theme.space5) {
                                // A hairline, not a Divider: the back is revealed *below*
                                // the front rather than split away from it.
                                Rectangle()
                                    .fill(.separator)
                                    .frame(height: 1)
                                fieldStack(fields(front: false))
                            }
                            .transition(revealTransition)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
                }
            }
            .frame(maxHeight: .infinity)
            controls
        }
        .padding(Theme.space6)
        .cardSurface()
    }

    @ViewBuilder
    private var controls: some View {
        if model.revealed {
            HStack(spacing: Theme.space2) {
                ForEach(Rating.allCases, id: \.self) { rating in
                    RatingButton(rating: rating, interval: model.intervalLabel(for: rating)) {
                        Task {
                            await model.grade(rating)
                            onGraded()
                        }
                    }
                }
            }
        } else {
            Button("Show Answer") {
                withAnimation(revealAnimation) { model.revealed = true }
            }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .frame(width: 200)
            .help("Press Space")
        }
    }

    /// Soft "flip" feel without literal 3D; plain fade when motion is reduced.
    private var revealAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.15)
    }

    private var revealTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    @ViewBuilder
    private func fieldStack(_ fields: [NoteType.RenderableField]) -> some View {
        VStack(spacing: Theme.space3) {
            if fields.isEmpty {
                // Dangling template (see `fields(front:)`) or an all-empty side —
                // say so rather than render a blank card the user cannot interpret.
                Text("This side has no content.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(fields.indices, id: \.self) { FieldContentView(fields[$0]) }
            }
        }
        .font(.title2)
        .lineSpacing(Theme.space1)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
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

/// One of the four answer capsules: rating colour on a wash of itself, with the
/// preview interval as a caption underneath the name.
private struct RatingButton: View {
    let rating: Rating
    let interval: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.space1 / 2) {
                Text(StudyCardView.title(of: rating))
                Text(interval)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.space2)
            .foregroundStyle(Theme.color(for: rating))
            .background(Theme.color(for: rating).opacity(isHovering ? 0.22 : 0.13), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue)")), modifiers: [])
        .help("Press \(rating.rawValue)")
        .accessibilityLabel(
            "\(StudyCardView.title(of: rating)), next in \(interval)"
        )
    }
}
