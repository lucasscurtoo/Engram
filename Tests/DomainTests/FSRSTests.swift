import Foundation
import Testing
import Domain

/// 2025-01-01 12:00:00 UTC — same start instant the vector generator uses.
private let start = Date(timeIntervalSince1970: 1_735_732_800)

private func newCard(createdAt: Date = start) -> Card {
    Card(noteID: UUID(), templateIndex: 0, deckID: UUID(), createdAt: createdAt)
}

@Suite("FSRS v5 vs py-fsrs 4.1.2 reference vectors")
struct FSRSTests {
    private func domainState(_ pyState: Int) -> CardState {
        switch pyState {
        case 1: .learning
        case 2: .review
        case 3: .relearning
        default: fatalError("unknown py-fsrs state \(pyState)")
        }
    }

    @Test(arguments: FSRSTestVectors.scenarios.map(\.name))
    func replaysReferenceScenario(_ name: String) throws {
        let scenario = try #require(FSRSTestVectors.scenarios.first { $0.name == name })
        let fsrs = FSRS()
        var card = newCard()
        for (index, step) in scenario.steps.enumerated() {
            let now = start.addingTimeInterval(step.reviewOffset)
            let rating = try #require(Rating(rawValue: step.rating))
            let info = fsrs.review(card: card, rating: rating, now: now)
            card = info.card

            let at = "\(scenario.name)[\(index)]"
            #expect(card.state == domainState(step.state), "\(at) state")
            #expect(card.step == step.step, "\(at) step")
            #expect(abs(card.stability - step.stability) < 1e-4, "\(at) stability \(card.stability) vs \(step.stability)")
            #expect(abs(card.difficulty - step.difficulty) < 1e-4, "\(at) difficulty \(card.difficulty) vs \(step.difficulty)")
            #expect(abs(info.interval - step.intervalSeconds) < 1, "\(at) interval \(info.interval) vs \(step.intervalSeconds)")
            #expect(card.due == now.addingTimeInterval(info.interval), "\(at) due")
        }
    }

    @Test func scheduleReturnsAllFourRatingsAndMatchesReview() {
        let fsrs = FSRS()
        let card = newCard()
        let options = fsrs.schedule(card: card, now: start)
        #expect(Set(options.keys) == Set(Rating.allCases))
        for rating in Rating.allCases {
            #expect(options[rating] == fsrs.review(card: card, rating: rating, now: start))
        }
    }

    @Test func intervalsAreMonotonicAcrossRatingsForReviewCards() {
        // M4 acceptance backstop: Easy > Good > Hard > Again on a mature card.
        let fsrs = FSRS()
        var card = newCard()
        card = fsrs.review(card: card, rating: .easy, now: start).card // graduate to .review
        let now = card.due
        let options = fsrs.schedule(card: card, now: now)
        let (again, hard, good, easy) = (
            options[.again]!.interval, options[.hard]!.interval,
            options[.good]!.interval, options[.easy]!.interval
        )
        #expect(again < hard)
        #expect(hard <= good)
        #expect(good < easy)
    }

    @Test func lapseIncrementsLapsesAndEntersRelearning() {
        let fsrs = FSRS()
        var card = newCard()
        card = fsrs.review(card: card, rating: .easy, now: start).card
        let lapsed = fsrs.review(card: card, rating: .again, now: card.due).card
        #expect(lapsed.state == .relearning)
        #expect(lapsed.lapses == 1)
        #expect(lapsed.step == 0)
    }

    @Test func repsCountEveryReview() {
        let fsrs = FSRS()
        var card = newCard()
        for _ in 0..<3 {
            card = fsrs.review(card: card, rating: .good, now: card.due).card
        }
        #expect(card.reps == 3)
    }
}
