import SwiftUI
import Domain

/// Seam 2: how a raw field string becomes a view. Adding LaTeX/code/images means
/// adding a renderer + a case in FieldContentView — nothing else changes.
protocol ContentRenderer<Output> {
    associatedtype Output: View
    func render(_ raw: String) -> Output
}

/// Renders one note field according to its declared content type.
/// All note/card content in the app flows through here.
struct FieldContentView: View {
    let def: FieldDef
    let content: String

    init(def: FieldDef, content: String) {
        self.def = def
        self.content = content
    }

    /// Preferred entry point for card sides: `noteType.frontFields(...)` / `backFields(...)`.
    init(_ field: NoteType.RenderableField) {
        self.init(def: field.def, content: field.content)
    }

    var body: some View {
        switch def.contentType {
        case .markdown:
            MarkdownRenderer().render(content)
        // TODO(owner): plug LaTeXRenderer here ($...$ / $$...$$ via KaTeX in WKWebView).
        }
    }
}
