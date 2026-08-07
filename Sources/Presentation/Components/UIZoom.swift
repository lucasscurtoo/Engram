import SwiftUI

/// App-wide zoom (⌘+ / ⌘= / ⌘- / ⌘0).
///
/// Not `dynamicTypeSize`: macOS has no Dynamic Type, and setting that environment
/// value changes nothing on this platform (verified on 14 — the same view renders
/// identically at `.large` and `.xxLarge`). So zoom is a real geometry scale: the
/// content is laid out at `size / scale` and scaled back up, which magnifies type,
/// padding, icons and hairlines together instead of only the fonts.
///
/// Applied per scene root, because `@AppStorage` is per-view and because macOS
/// sheets are their own windows — they scale themselves (`ReviewSessionView`).
enum UIZoom {
    /// Seven steps around 1.0, matching the seven non-accessibility Dynamic Type
    /// sizes the menu is modelled on.
    static let scales: [CGFloat] = [0.7, 0.8, 0.9, 1.0, 1.15, 1.3, 1.5]

    /// 1.0 — an untouched install looks untouched.
    static let defaultIndex = 3

    static let storageKey = "ui.zoom"

    static func scale(at index: Int) -> CGFloat {
        scales[min(max(index, 0), scales.count - 1)]
    }

    static func zoomedIn(from index: Int) -> Int { min(index + 1, scales.count - 1) }
    static func zoomedOut(from index: Int) -> Int { max(index - 1, 0) }
}

extension View {
    /// Applies the persisted zoom. Needs a container that proposes a size — a window
    /// root or an explicitly framed sheet body, never a self-sizing view.
    func uiZoom() -> some View {
        modifier(UIZoomModifier())
    }
}

private struct UIZoomModifier: ViewModifier {
    @AppStorage(UIZoom.storageKey) private var index = UIZoom.defaultIndex

    func body(content: Content) -> some View {
        let scale = UIZoom.scale(at: index)
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width / scale, height: proxy.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
        }
        .background {
            // ⌘= alias for Zoom In. It lives in the view tree rather than in the
            // menu so the View menu shows one "Zoom In ⌘+" and not two.
            Button("Zoom In") { index = UIZoom.zoomedIn(from: index) }
                .keyboardShortcut("=", modifiers: [.command])
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }
}

/// The View-menu entries. Split out so it can own `@AppStorage`, which `App` bodies
/// cannot read directly.
struct ZoomCommands: View {
    @AppStorage(UIZoom.storageKey) private var index = UIZoom.defaultIndex

    var body: some View {
        Button("Zoom In") { index = UIZoom.zoomedIn(from: index) }
            .keyboardShortcut("+", modifiers: [.command])
            .disabled(index >= UIZoom.scales.count - 1)
        Button("Zoom Out") { index = UIZoom.zoomedOut(from: index) }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(index <= 0)
        Button("Actual Size") { index = UIZoom.defaultIndex }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(index == UIZoom.defaultIndex)
    }
}
