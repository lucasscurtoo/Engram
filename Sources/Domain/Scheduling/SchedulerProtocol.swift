import Foundation

/// Scheduling engine seam. FSRS is the MVP implementation.
public protocol Scheduler: Sendable {
    /// Given a card's current state and the moment of review, returns the outcome
    /// for every possible rating — one entry per `Rating` — so the UI can show
    /// "how far each button postpones" (like Anki).
    func schedule(card: Card, now: Date) -> [Rating: SchedulingInfo]
}
