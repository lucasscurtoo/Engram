/// The four self-assessment grades of a review. Raw values match FSRS/Anki.
public enum Rating: Int, CaseIterable, Sendable, Codable, Hashable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4
}
