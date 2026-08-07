/// FSRS card lifecycle. `.new` means never reviewed (no stability/difficulty yet).
public enum CardState: Int, CaseIterable, Sendable, Codable, Hashable {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3
}
