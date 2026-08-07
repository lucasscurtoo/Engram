import SwiftUI
import WebKit

/// Math renderer: `$…$` / `$$…$$` inside otherwise plain text, typeset by the
/// vendored KaTeX in a `WKWebView`. Fully offline — the shell, the CSS, the JS and
/// the fonts all live in `Resources/KaTeX`, loaded with that directory as the only
/// read-access root, so the view can never reach the network.
///
/// The webview is display-only: it never becomes first responder (`hitTest` returns
/// nil), so the note editor's `TextEditor` keeps focus while the preview updates.
///
/// Height is reported back from the page and drives the SwiftUI frame, so the math
/// participates in layout instead of scrolling inside its own box.
struct LaTeXRenderer: View {
    let content: String

    /// Whole environment: `Color.resolve(in:)` needs it, and reading it re-renders
    /// the page when the colour scheme flips.
    @Environment(\.self) private var environment
    @Environment(\.latexFontSize) private var fontSize
    @State private var height: CGFloat = minHeight

    private static let minHeight: CGFloat = 24

    var body: some View {
        MathWebView(content: content, color: cssTextColor, fontSize: fontSize, height: $height)
            .frame(height: max(height, Self.minHeight))
            .frame(maxWidth: .infinity)
    }

    /// The webview has no access to the asset catalog, so the token is resolved for
    /// the current scheme here and pushed into the page as CSS.
    private var cssTextColor: String {
        let color = Theme.textPrimary.resolve(in: environment)
        return String(
            format: "rgba(%.0f,%.0f,%.0f,%.3f)",
            color.red * 255, color.green * 255, color.blue * 255, color.opacity
        )
    }
}

/// Point size the math should match. Set alongside `.font(…)` wherever card content
/// is rendered; defaults to the body size.
private struct LaTeXFontSizeKey: EnvironmentKey {
    static let defaultValue = NSFont.preferredFont(forTextStyle: .body).pointSize
}

extension EnvironmentValues {
    var latexFontSize: CGFloat {
        get { self[LaTeXFontSizeKey.self] }
        set { self[LaTeXFontSizeKey.self] = newValue }
    }
}

extension View {
    /// Matches embedded math to the surrounding type scale.
    func latexFontSize(_ size: CGFloat) -> some View {
        environment(\.latexFontSize, size)
    }
}

// MARK: - Web view

private struct MathWebView: NSViewRepresentable {
    let content: String
    let color: String
    let fontSize: CGFloat
    @Binding var height: CGFloat

    /// Bundled shell + its read-access root. nil only if the resources went missing.
    private static let shell = Bundle.main.url(
        forResource: "render", withExtension: "html", subdirectory: "KaTeX"
    )

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "height")
        let webView = PassthroughWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        // Transparent so the card surface shows through in both schemes.
        webView.setValue(false, forKey: "drawsBackground")
        if let shell = Self.shell {
            webView.loadFileURL(shell, allowingReadAccessTo: shell.deletingLastPathComponent())
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(content: content, color: color, fontSize: fontSize, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "height")
    }

    /// Never steals the click or the keyboard: the study card stays selectable and
    /// the editor's TextEditor keeps first responder while previewing.
    private final class PassthroughWebView: WKWebView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var acceptsFirstResponder: Bool { false }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let height: Binding<CGFloat>
        private var isLoaded = false
        private var pending: (content: String, color: String, fontSize: CGFloat)?

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        /// Re-renders on content, colour-scheme and zoom changes alike; calls that
        /// arrive before the shell finishes loading are replayed on load.
        func render(content: String, color: String, fontSize: CGFloat, in webView: WKWebView) {
            guard isLoaded else {
                pending = (content, color, fontSize)
                return
            }
            webView.evaluateJavaScript("render(\(json(content)), \(json(color)), \(fontSize));")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            if let pending {
                self.pending = nil
                render(content: pending.content, color: pending.color, fontSize: pending.fontSize, in: webView)
            }
        }

        func userContentController(
            _ controller: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            guard let value = message.body as? NSNumber else { return }
            let new = CGFloat(value.doubleValue)
            if abs(new - height.wrappedValue) > 0.5 { height.wrappedValue = new }
        }

        /// A JSON string literal is a JS string literal — the safe way to inject a
        /// raw field into a script. Encoded inside an array because a bare string is
        /// not a valid top-level JSON document.
        private func json(_ string: String) -> String {
            guard let data = try? JSONEncoder().encode([string]),
                  let text = String(data: data, encoding: .utf8)
            else { return "\"\"" }
            return String(text.dropFirst().dropLast())
        }
    }
}
