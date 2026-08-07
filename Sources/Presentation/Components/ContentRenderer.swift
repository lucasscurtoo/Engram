import SwiftUI
import Domain

/// Seam 2: how a raw field string becomes a view. Adding LaTeX/code/images means
/// adding a renderer + a case in FieldContentView — nothing else changes.
protocol ContentRenderer<Output> {
    associatedtype Output: View
    func render(_ raw: String) -> Output
}

/// Renders one resolved note field according to its declared content type.
/// All card content in the app flows through here.
struct FieldContentView: View {
    let field: NoteType.RenderableField

    var body: some View {
        switch field.def.contentType {
        case .markdown:
            MarkdownRenderer().render(field.content)
        // TODO(owner): plug LaTeXRenderer here ($...$ / $$...$$ via KaTeX in WKWebView).
        }
    }
}
