import Foundation

/// FSRS v5 scheduler, ported line-by-line from py-fsrs 4.1.2
/// (github.com/open-spaced-repetition/py-fsrs). The reference vectors in
/// Tests/DomainTests/FSRSTestVectors.swift are generated from that exact
/// implementation (Scripts/generate_fsrs_vectors.py); keep both in sync.
public struct FSRS: Scheduler {
    static let decay: Double = -0.5
    static let factor: Double = pow(0.9, 1 / decay) - 1

    public let parameters: FSRSParameters
    private var w: [Double] { parameters.weights }

    public init(parameters: FSRSParameters = FSRSParameters()) {
        self.parameters = parameters
    }

    public func schedule(card: Card, now: Date) -> [Rating: SchedulingInfo] {
        Dictionary(uniqueKeysWithValues: Rating.allCases.map { rating in
            (rating, review(card: card, rating: rating, now: now))
        })
    }

    /// Applies one review. Pure: returns the updated card, mutates nothing.
    public func review(card: Card, rating: Rating, now: Date) -> SchedulingInfo {
        var card = card
        let stateBefore = card.state
        let daysSinceLastReview = card.lastReview.map { fullDays(from: $0, to: now) }
        let isSameDay = (daysSinceLastReview ?? Int.max) < 1

        // Memory state update (stability / difficulty).
        if stateBefore == .new {
            card.stability = initialStability(rating)
            card.difficulty = initialDifficulty(rating)
        } else if isSameDay {
            card.stability = shortTermStability(card.stability, rating: rating)
            card.difficulty = nextDifficulty(card.difficulty, rating: rating)
        } else {
            let retrievability = retrievability(
                stability: card.stability,
                elapsedDays: max(0, daysSinceLastReview ?? 0)
            )
            card.stability = nextStability(
                difficulty: card.difficulty, stability: card.stability,
                retrievability: retrievability, rating: rating
            )
            card.difficulty = nextDifficulty(card.difficulty, rating: rating)
        }

        // State transition + next interval.
        var interval: TimeInterval
        switch stateBefore {
        case .new, .learning:
            card.state = .learning
            interval = stepInterval(card: &card, rating: rating, steps: parameters.learningSteps)
        case .review:
            if rating == .again {
                card.lapses += 1
                if parameters.relearningSteps.isEmpty {
                    interval = daysToInterval(nextIntervalDays(stability: card.stability))
                } else {
                    card.state = .relearning
                    card.step = 0
                    interval = parameters.relearningSteps[0]
                }
            } else {
                interval = daysToInterval(nextIntervalDays(stability: card.stability))
            }
        case .relearning:
            interval = stepInterval(card: &card, rating: rating, steps: parameters.relearningSteps)
        }

        if parameters.enableFuzzing, card.state == .review {
            interval = fuzzedInterval(interval)
        }

        card.due = now.addingTimeInterval(interval)
        card.lastReview = now
        card.reps += 1
        return SchedulingInfo(card: card, interval: interval)
    }

    // MARK: - Step walking (identical logic for learning and relearning in py-fsrs)

    private func stepInterval(card: inout Card, rating: Rating, steps: [TimeInterval]) -> TimeInterval {
        let step = card.step ?? 0
        // step > steps.count covers cards scheduled by a config with more steps than now.
        if steps.isEmpty || step > steps.count {
            return graduate(&card)
        }
        switch rating {
        case .again:
            card.step = 0
            return steps[0]
        case .hard:
            // Step stays the same; first-step Hard interpolates between the steps.
            if step == 0, steps.count == 1 { return steps[0] * 1.5 }
            if step == 0, steps.count >= 2 { return (steps[0] + steps[1]) / 2 }
            return steps[step]
        case .good:
            if step + 1 == steps.count { return graduate(&card) }
            card.step = step + 1
            return steps[step + 1]
        case .easy:
            return graduate(&card)
        }
    }

    private func graduate(_ card: inout Card) -> TimeInterval {
        card.state = .review
        card.step = nil
        return daysToInterval(nextIntervalDays(stability: card.stability))
    }

    // MARK: - FSRS v5 formulas

    func retrievability(stability: Double, elapsedDays: Int) -> Double {
        pow(1 + Self.factor * Double(elapsedDays) / stability, Self.decay)
    }

    private func initialStability(_ rating: Rating) -> Double {
        max(w[rating.rawValue - 1], 0.1)
    }

    private func initialDifficulty(_ rating: Rating) -> Double {
        clampDifficulty(w[4] - exp(w[5] * Double(rating.rawValue - 1)) + 1)
    }

    private func nextDifficulty(_ difficulty: Double, rating: Rating) -> Double {
        let delta = -w[6] * Double(rating.rawValue - 3)
        let damped = difficulty + delta * (10 - difficulty) / 9
        let meanReverted = w[7] * initialDifficulty(.easy) + (1 - w[7]) * damped
        return clampDifficulty(meanReverted)
    }

    /// Same-day review update (FSRS v5 short-term memory model).
    private func shortTermStability(_ stability: Double, rating: Rating) -> Double {
        stability * exp(w[17] * (Double(rating.rawValue - 3) + w[18]))
    }

    private func nextStability(
        difficulty: Double, stability: Double, retrievability: Double, rating: Rating
    ) -> Double {
        if rating == .again {
            let longTerm = w[11]
                * pow(difficulty, -w[12])
                * (pow(stability + 1, w[13]) - 1)
                * exp((1 - retrievability) * w[14])
            // Post-lapse stability is capped by the short-term formula, not by S itself.
            let shortTermCap = stability / exp(w[17] * w[18])
            return min(longTerm, shortTermCap)
        }
        let hardPenalty = rating == .hard ? w[15] : 1
        let easyBonus = rating == .easy ? w[16] : 1
        return stability * (
            1
            + exp(w[8])
            * (11 - difficulty)
            * pow(stability, -w[9])
            * (exp((1 - retrievability) * w[10]) - 1)
            * hardPenalty
            * easyBonus
        )
    }

    private func nextIntervalDays(stability: Double) -> Int {
        let raw = stability / Self.factor * (pow(parameters.requestRetention, 1 / Self.decay) - 1)
        // py-fsrs uses Python round() (banker's rounding); .toNearestOrEven matches it.
        var days = Int(raw.rounded(.toNearestOrEven))
        days = max(days, 1)
        return min(days, parameters.maximumIntervalDays)
    }

    private func clampDifficulty(_ value: Double) -> Double {
        min(max(value, 1), 10)
    }

    private func daysToInterval(_ days: Int) -> TimeInterval {
        Double(days) * 86_400
    }

    /// Python timedelta.days semantics: whole days, floored.
    private func fullDays(from: Date, to: Date) -> Int {
        Int((to.timeIntervalSince(from) / 86_400).rounded(.down))
    }

    // MARK: - Fuzz (port of py-fsrs _get_fuzzed_interval; only used when enableFuzzing)

    private static let fuzzRanges: [(start: Double, end: Double, factor: Double)] = [
        (2.5, 7.0, 0.15),
        (7.0, 20.0, 0.1),
        (20.0, .infinity, 0.05),
    ]

    private func fuzzedInterval(_ interval: TimeInterval) -> TimeInterval {
        let intervalDays = Int(interval / 86_400)
        guard Double(intervalDays) >= 2.5 else { return interval }

        var delta = 1.0
        for range in Self.fuzzRanges {
            delta += range.factor * max(min(Double(intervalDays), range.end) - range.start, 0)
        }
        var minDays = Int((Double(intervalDays) - delta).rounded(.toNearestOrEven))
        var maxDays = Int((Double(intervalDays) + delta).rounded(.toNearestOrEven))
        minDays = max(2, minDays)
        maxDays = min(maxDays, parameters.maximumIntervalDays)
        minDays = min(minDays, maxDays)

        let fuzzed = Double.random(in: 0..<1) * Double(maxDays - minDays + 1) + Double(minDays)
        let days = min(Int(fuzzed.rounded(.toNearestOrEven)), parameters.maximumIntervalDays)
        return daysToInterval(days)
    }
}
