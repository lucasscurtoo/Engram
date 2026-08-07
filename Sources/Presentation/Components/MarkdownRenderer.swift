import SwiftUI

/// MVP renderer: Foundation's markdown parsing, zero dependencies.
/// Bold, inline code, links — enough for sign rules and simple exercises.
struct MarkdownRenderer: ContentRenderer {
    func render(_ raw: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return Text((try? AttributedString(markdown: raw, options: options)) ?? AttributedString(raw))
    }
}
