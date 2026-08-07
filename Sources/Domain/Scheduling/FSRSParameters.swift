import Foundation

/// Configuration for the FSRS v5 scheduler. Defaults mirror py-fsrs 4.1.2.
public struct FSRSParameters: Sendable, Codable, Hashable {
    /// FSRS v5 default weights published by open-spaced-repetition (19 values).
    public static let defaultWeights: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604,
        0.0046, 1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605,
        2.2698, 0.2315, 2.9898, 0.51655, 0.6621,
    ]

    public var weights: [Double]
    public var requestRetention: Double
    /// Intra-day steps (seconds) a card walks through in `.learning` before graduating.
    public var learningSteps: [TimeInterval]
    /// Steps (seconds) after a lapse, in `.relearning`.
    public var relearningSteps: [TimeInterval]
    public var maximumIntervalDays: Int
    /// Anki-style interval fuzz. Off by default so scheduling is deterministic and testable.
    public var enableFuzzing: Bool

    public init(
        weights: [Double] = Self.defaultWeights,
        requestRetention: Double = 0.9,
        learningSteps: [TimeInterval] = [60, 600],
        relearningSteps: [TimeInterval] = [600],
        maximumIntervalDays: Int = 36_500,
        enableFuzzing: Bool = false
    ) {
        precondition(weights.count == 19, "FSRS v5 requires exactly 19 weights")
        self.weights = weights
        self.requestRetention = requestRetention
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.maximumIntervalDays = maximumIntervalDays
        self.enableFuzzing = enableFuzzing
    }

    /// Per-deck parameters (seam 6): retention comes from the deck's config.
    /// TODO(owner): per-deck optimized weights post-MVP.
    public init(deckConfig: DeckConfig) {
        self.init(requestRetention: deckConfig.requestRetention)
    }
}
