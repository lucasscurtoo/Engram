import Domain
import SwiftUI

/// The app's design tokens. Every spacing, radius, colour and elevation used by the
/// Presentation layer comes from here — views never spell out a number or a hex.
///
/// Colours are asset-catalog entries so light and dark are resolved by the system;
/// there is deliberately no `Color(hex:)` helper anywhere in the app.
enum Theme {
    // MARK: - Spacing

    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 24
    static let space6: CGFloat = 32

    // MARK: - Radii

    enum Radius {
        /// Study card and other large floating surfaces.
        static let card: CGFloat = 16
        /// Stat tiles.
        static let tile: CGFloat = 12
        /// Buttons, fields, row highlights.
        static let control: CGFloat = 8
    }

    // MARK: - Colours

    /// Wired as the global accent in project.yml, so system controls pick it up for free.
    static let accent = Color("AccentColor")
    /// Backdrop behind the study card (review sheet, running focus screen).
    static let studyBackdrop = Color("StudyBackdrop")
    /// Fill of anything `.cardSurface()` — white in light, a raised grey in dark.
    static let cardSurface = Color("CardSurface")
    /// 8% black in light, fully transparent in dark: dark-mode depth comes from the
    /// surface colour, not from a shadow.
    static let cardShadow = Color("CardShadow")

    /// Muted rating colours. `.good` is the accent so the expected answer reads as
    /// "the app's colour" rather than a fifth hue.
    static func color(for rating: Rating) -> Color {
        switch rating {
        case .again: Color("RatingAgain")
        case .hard: Color("RatingHard")
        case .good: accent
        case .easy: Color("RatingEasy")
        }
    }

    // MARK: - Elevation

    static let shadowRadius: CGFloat = 12
    static let shadowOffsetY: CGFloat = 2
}

extension View {
    /// The one elevated surface in the app: study card, stat tiles, floating panels.
    func cardSurface(radius: CGFloat = Theme.Radius.card) -> some View {
        background(Theme.cardSurface, in: .rect(cornerRadius: radius))
            .shadow(color: Theme.cardShadow, radius: Theme.shadowRadius, y: Theme.shadowOffsetY)
    }
}

/// Quiet "big number" tile — the review summary and the stats dashboard share it.
struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space1) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.space4)
        .cardSurface(radius: Theme.Radius.tile)
        // One VoiceOver stop per tile: "Retention, 87%".
        .accessibilityElement(children: .combine)
    }
}
