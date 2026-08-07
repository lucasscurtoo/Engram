import Domain
import SwiftUI

/// One card of the review flow: front → "Show Answer" → back + the four ratings with
/// their preview intervals. Sides always come from `noteType.frontFields/backFields`
/// and render through `FieldContentView` — never a hardcoded note field.
///
/// Extracted from `ReviewSessionView` (M4, behaviour unchanged) so focus mode can
/// embed the exact same study UI instead of duplicating it.
///
/// The view carries its own `.panel()` so the review sheet and the focus screen get
/// the identical card without either of them restating the surface.
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
            // Short cards sit vertically centered; long ones grow and scroll.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: Theme.space5) {
                        fieldStack(fields(front: true))
                        if model.revealed {
                            VStack(spacing: Theme.space5) {
                                // A hairline, not a Divider: the back is revealed *below*
                                // the front rather than split away from it.
                                Rectangle()
                                    .fill(Theme.hairline)
                                    .frame(height: Theme.hairlineWidth)
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
        .panel()
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
            Button {
                withAnimation(revealAnimation) { model.revealed = true }
            } label: {
                HStack(spacing: Theme.space2) {
                    Text("Show Answer")
                    KeyHint("␣", onAccent: true)
                }
                .frame(width: 200)
            }
            .keyboardShortcut(.space, modifiers: [])
            .buttonStyle(AccentButtonStyle(verticalPadding: Theme.space2 + 2))
            .help("Press Space")
            .accessibilityLabel("Show Answer")
        }
    }

    /// Pro, not playful: opacity plus a 4pt rise, no bounce. Plain fade when motion
    /// is reduced.
    private var revealAnimation: Animation {
        .easeOut(duration: Theme.reveal)
    }

    private var revealTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4))
    }

    @ViewBuilder
    private func fieldStack(_ fields: [NoteType.RenderableField]) -> some View {
        VStack(spacing: Theme.space3) {
            if fields.isEmpty {
                // Dangling template (see `fields(front:)`) or an all-empty side —
                // say so rather than render a blank card the user cannot interpret.
                Text("This side has no content.")
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(fields.indices, id: \.self) { FieldContentView(fields[$0]) }
            }
        }
        .font(.title2.weight(.medium))
        .latexFontSize(NSFont.preferredFont(forTextStyle: .title2).pointSize)
        .foregroundStyle(Theme.textPrimary)
        .lineSpacing(Theme.space1)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .textSelection(.enabled)
    }

    /// `sideFields` handles every note type (basic templates, cloze markers,
    /// parametric substitution via the item's seed) and returns nil for a stale
    /// `templateIndex` instead of trapping.
    private func fields(front: Bool) -> [NoteType.RenderableField] {
        item.noteType.sideFields(
            of: item.note, templateIndex: item.card.templateIndex,
            front: front, seed: item.parametricSeed
        ) ?? []
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

/// One of the four answer blocks: a raised rectangle that borrows the rating's colour
/// on hover, with the preview interval in mono underneath and the key number tucked
/// into the top-right corner.
private struct RatingButton: View {
    let rating: Rating
    let interval: String
    let action: () -> Void

    @State private var isHovering = false

    private var tint: Color { Theme.color(for: rating) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(StudyCardView.title(of: rating))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(tint)
                // Empty in modes without scheduling (cram): no caption at all.
                if !interval.isEmpty {
                    Text(interval)
                        .font(Theme.mono(.callout))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.space3)
            .raised(
                fill: isHovering ? tint.opacity(0.10) : Theme.bg2,
                border: isHovering ? tint : Theme.hairline
            )
            .overlay(alignment: .topTrailing) {
                KeyHint("\(rating.rawValue)").padding(Theme.space1)
            }
        }
        .buttonStyle(.pressable)
        .onHover { isHovering = $0 }
        .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue)")), modifiers: [])
        .help("Press \(rating.rawValue)")
        .accessibilityLabel(
            interval.isEmpty
                ? StudyCardView.title(of: rating)
                : "\(StudyCardView.title(of: rating)), next in \(interval)"
        )
    }
}
