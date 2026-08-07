import Foundation

/// Anki-style cloze markers: `{{c1::answer}}` or `{{c1::answer::hint}}`.
/// One card per distinct number; the studied side hides that number's answers
/// and shows every other marker resolved.
public enum Cloze {
    private struct Marker {
        let range: Range<String.Index>
        let number: Int
        let answer: String
        let hint: String?
    }

    // Computed: Regex isn't Sendable, so a stored static trips Swift 6 checking.
    private static var pattern: Regex<(Substring, Substring, Substring)> { /\{\{c(\d+)::(.+?)\}\}/ }

    private static func markers(in text: String) -> [Marker] {
        text.matches(of: pattern).compactMap { match in
            guard let number = Int(match.output.1), number > 0 else { return nil }
            let body = String(match.output.2)
            // First "::" splits answer from optional hint.
            if let separator = body.range(of: "::") {
                return Marker(
                    range: match.range, number: number,
                    answer: String(body[..<separator.lowerBound]),
                    hint: String(body[separator.upperBound...])
                )
            }
            return Marker(range: match.range, number: number, answer: body, hint: nil)
        }
    }

    /// Distinct marker numbers, ascending. Empty = not a (valid) cloze note.
    public static func indices(in text: String) -> [Int] {
        Set(markers(in: text).map(\.number)).sorted()
    }

    /// Question side: `number`'s answers become `[hint]`/`[…]`, the rest resolve to plain text.
    public static func front(_ text: String, hiding number: Int) -> String {
        replaceMarkers(in: text) { marker in
            marker.number == number ? "**[\(marker.hint ?? "…")]**" : marker.answer
        }
    }

    /// Answer side: `number`'s answers bolded, the rest plain.
    public static func back(_ text: String, revealing number: Int) -> String {
        replaceMarkers(in: text) { marker in
            marker.number == number ? "**\(marker.answer)**" : marker.answer
        }
    }

    private static func replaceMarkers(in text: String, _ replacement: (Marker) -> String) -> String {
        var result = text
        for marker in markers(in: text).reversed() {
            result.replaceSubrange(marker.range, with: replacement(marker))
        }
        return result
    }
}
