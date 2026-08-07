import Foundation

/// Result of applying one rating to a card: the updated card and the interval assigned.
/// The scheduler returns one of these per rating so the UI can preview all four buttons.
public struct SchedulingInfo: Sendable, Hashable {
    public let card: Card
    /// Seconds until the card is due again.
    public let interval: TimeInterval

    public init(card: Card, interval: TimeInterval) {
        self.card = card
        self.interval = interval
    }
}
