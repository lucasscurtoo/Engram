import Domain
import SwiftUI

/// The app's design tokens. Every spacing, radius, colour and elevation used by the
/// Presentation layer comes from here — views never spell out a number or a hex.
///
/// Direction: dark-pro. Depth is built from *layered near-black surfaces plus a
/// hairline border*, never from shadows (a shadow on near-black is invisible and
/// only muddies the edge). Light mode reuses the same layer stack inverted and adds
/// the one soft shadow that dark mode does not need.
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

    /// Tighter than a "friendly" app on purpose: rectangular reads technical,
    /// capsules read soft.
    enum Radius {
        /// Study card, panels, sheet surfaces.
        static let card: CGFloat = 12
        /// Stat tiles.
        static let tile: CGFloat = 10
        /// Buttons, fields, row highlights, rating blocks.
        static let control: CGFloat = 6
        /// Key-hint chips and other micro-surfaces.
        static let chip: CGFloat = 4
    }

    // MARK: - Surfaces

    /// Window and study backdrop — the floor everything else sits on.
    static let bg0 = Color("BG0")
    /// Content surface: panels, cards, list bodies, headers.
    static let bg1 = Color("BG1")
    /// Raised: fields, rating blocks, tiles, key hints.
    static let bg2 = Color("BG2")
    /// Hover.
    static let bg3 = Color("BG3")
    /// White 8% in dark, black 8% in light. The single depth device.
    static let hairline = Color("BorderHairline")
    static let hairlineWidth: CGFloat = 1

    // MARK: - Text

    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let textTertiary = Color("TextTertiary")

    // MARK: - Accent

    /// Wired as the global accent in project.yml, so system controls pick it up for free.
    static let accent = Color("AccentColor")
    /// The accent at 30%, used only as a glow behind accent-filled controls.
    static var accentGlow: Color { accent.opacity(0.30) }
    /// Selected-row wash in the sidebar.
    static var accentWash: Color { accent.opacity(0.12) }

    /// 8% black in light, fully transparent in dark: dark-mode depth comes from the
    /// layer colour and its hairline, not from a shadow.
    static let cardShadow = Color("CardShadow")
    static let shadowRadius: CGFloat = 10
    static let shadowOffsetY: CGFloat = 2

    // MARK: - Ratings

    /// Vivid in dark, dimmed in light. `.good` is the accent so the expected answer
    /// reads as "the app's colour" rather than a fifth hue.
    static func color(for rating: Rating) -> Color {
        switch rating {
        case .again: Color("RatingAgain")
        case .hard: Color("RatingHard")
        case .good: accent
        case .easy: Color("RatingEasy")
        }
    }

    /// Card states borrow the rating palette wherever the two map onto each other,
    /// so the donut and the answer buttons never disagree about what "hard" looks like.
    static func color(for state: CardState) -> Color {
        switch state {
        case .new: textTertiary
        case .learning: color(for: .hard)
        case .review: accent
        case .relearning: color(for: .again)
        }
    }

    // MARK: - Type

    /// Fixed-size monospace. Only for the glanceable focus timers, which must not
    /// reflow; everything else uses the semantic overload so it scales with zoom.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// The signature: every *datum* — interval, count, stat, tag — is monospaced,
    /// and semantic so app zoom and Dynamic Type both reach it.
    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }

    // MARK: - Motion

    /// Keyboard-repeated actions (grading) — never longer than this.
    static let quick: Double = 0.12
    /// Deliberate reveals.
    static let reveal: Double = 0.18
}

// MARK: - Surface modifiers

extension View {
    /// The content surface: study card, sheets, stat tiles, chart panels.
    func panel(radius: CGFloat = Theme.Radius.card) -> some View {
        background(Theme.bg1, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth)
            }
            .shadow(color: Theme.cardShadow, radius: Theme.shadowRadius, y: Theme.shadowOffsetY)
    }

    /// One layer above the content surface: fields, rating blocks, control rows.
    func raised(
        radius: CGFloat = Theme.Radius.control,
        fill: Color = Theme.bg2,
        border: Color = Theme.hairline
    ) -> some View {
        background(fill, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(border, lineWidth: Theme.hairlineWidth)
            }
    }

    /// Hairline rule under a header or filter bar — the dense screens' only separator.
    func bottomHairline() -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: Theme.hairlineWidth)
        }
    }
}

// MARK: - Type helpers

extension View {
    /// Section header treatment: 11pt uppercase, tracked, tertiary. "LIBRARY", "GOAL".
    func sectionCaps() -> some View {
        font(.subheadline.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
            .textCase(.uppercase)
    }
}

/// Mini-caps section header. Pairs with `.sectionCaps()` for ad-hoc labels.
struct SectionCaps: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).sectionCaps()
    }
}

// MARK: - Key hints

/// Tiny monospaced keycap chip shown next to (never instead of) a control's label,
/// e.g. ⏎, ␣, 1, ⌘S. Hidden from VoiceOver: the control's own label and `.help`
/// already announce the shortcut.
struct KeyHint: View {
    let key: String
    /// Chips sitting on an accent-filled button need their own contrast.
    var onAccent = false

    init(_ key: String, onAccent: Bool = false) {
        self.key = key
        self.onAccent = onAccent
    }

    var body: some View {
        Text(key)
            .font(Theme.mono(.caption, weight: .medium))
            .foregroundStyle(onAccent ? Color.white.opacity(0.85) : Theme.textSecondary)
            .padding(.horizontal, Theme.space1)
            .padding(.vertical, 1)
            .raised(
                radius: Theme.Radius.chip,
                fill: onAccent ? Color.white.opacity(0.18) : Theme.bg2,
                border: onAccent ? Color.white.opacity(0.22) : Theme.hairline
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Button styles

/// Press feedback for every custom button in the app: 0.98 scale, 120 ms ease-out,
/// skipped entirely when the user asked for reduced motion.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: PressableButtonStyle.Configuration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(.easeOut(duration: Theme.quick), value: configuration.isPressed)
                .contentShape(Rectangle())
        }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// The app's one strong control: accent fill, rectangular, faint accent glow.
/// Study, Show Answer, Start Focus and Save all share it.
struct AccentButtonStyle: ButtonStyle {
    var horizontalPadding: CGFloat = Theme.space4
    var verticalPadding: CGFloat = Theme.space2

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(
            configuration: configuration,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding
        )
    }

    private struct StyleBody: View {
        let configuration: AccentButtonStyle.Configuration
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(Theme.accent, in: .rect(cornerRadius: Theme.Radius.control))
                .shadow(color: Theme.accentGlow, radius: 8, y: 1)
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(.easeOut(duration: Theme.quick), value: configuration.isPressed)
                .contentShape(Rectangle())
        }
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accentAction: AccentButtonStyle { AccentButtonStyle() }
}

/// Quiet secondary control: raised block, hairline, secondary label. Used for the
/// browser's toolbar buttons, sheet Cancel, focus Pause/Stop.
struct QuietButtonStyle: ButtonStyle {
    var tint: Color = Theme.textSecondary

    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration, tint: tint)
    }

    private struct StyleBody: View {
        let configuration: QuietButtonStyle.Configuration
        let tint: Color

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.callout)
                .foregroundStyle(tint)
                .padding(.horizontal, Theme.space3)
                .padding(.vertical, Theme.space1 + 2)
                .raised(fill: isHovering && isEnabled ? Theme.bg3 : Theme.bg2)
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(.easeOut(duration: Theme.quick), value: configuration.isPressed)
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
        }
    }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}

// MARK: - Tiles

/// "Big number" tile — the review summary and the stats dashboard share it.
/// Label is mini-caps, value is monospaced: the house style for data.
struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            Text(title).sectionCaps()
            Text(value)
                .font(Theme.mono(.title, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.space4)
        .panel(radius: Theme.Radius.tile)
        // One VoiceOver stop per tile: "Retention, 87%".
        .accessibilityElement(children: .combine)
    }
}
