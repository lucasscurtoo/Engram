import Foundation
import Testing
import Domain
import Application

private let start = Date(timeIntervalSince1970: 1_735_732_800)

/// Records activate/deactivate calls so blocker discipline is assertable.
private actor SpyBlocker: DistractionBlocker {
    private(set) var calls: [String] = []
    func activate() { calls.append("on") }
    func deactivate() { calls.append("off") }
}

@Suite("FocusSessionService state machine")
struct FocusSessionServiceTests {
    private func makeService() -> (FocusSessionService, SpyBlocker) {
        let blocker = SpyBlocker()
        return (FocusSessionService(blocker: blocker), blocker)
    }

    private let pomodoro = FocusMode.pomodoro(PomodoroConfig(
        work: 25 * 60, shortBreak: 5 * 60, longBreak: 15 * 60, cyclesPerLongBreak: 4
    ))

    @Test func pomodoroWalksWorkBreakCycle() async {
        let (service, _) = makeService()
        var events = await service.start(mode: pomodoro, goal: nil, studyScope: nil, now: start)
        #expect(events == [.phaseStarted(.focusing)])
        #expect(await service.status(now: start).remaining == 25 * 60)

        // Mid-block: still focusing.
        events = await service.advance(now: start.addingTimeInterval(10 * 60))
        #expect(events.isEmpty)

        // Work block ends -> short break.
        events = await service.advance(now: start.addingTimeInterval(25 * 60))
        #expect(events == [.phaseStarted(.shortBreak)])
        let status = await service.status(now: start.addingTimeInterval(25 * 60))
        #expect(status.phase == .shortBreak)
        #expect(status.focusedSeconds == 25 * 60)
        #expect(status.completedFocusBlocks == 1)

        // Break ends -> focusing again.
        events = await service.advance(now: start.addingTimeInterval(30 * 60))
        #expect(events == [.phaseStarted(.focusing)])
    }

    @Test func fourthWorkBlockEarnsLongBreak() async {
        let (service, _) = makeService()
        _ = await service.start(mode: pomodoro, goal: nil, studyScope: nil, now: start)
        // 4 work blocks + 3 short breaks = 115 min; the 4th block ends at that mark.
        let events = await service.advance(now: start.addingTimeInterval(115 * 60))
        #expect(events.last == .phaseStarted(.longBreak))
        #expect(await service.status(now: start.addingTimeInterval(115 * 60)).completedFocusBlocks == 4)
    }

    @Test func catchUpProcessesMissedTransitions() async {
        let (service, _) = makeService()
        _ = await service.start(mode: pomodoro, goal: nil, studyScope: nil, now: start)
        // Mac slept through work + break entirely: both transitions arrive at once,
        // and only the completed work block counts as focused time.
        let events = await service.advance(now: start.addingTimeInterval(31 * 60))
        #expect(events == [.phaseStarted(.shortBreak), .phaseStarted(.focusing)])
        let status = await service.status(now: start.addingTimeInterval(31 * 60))
        #expect(status.phase == .focusing)
        #expect(status.focusedSeconds == 26 * 60) // 25 finished + 1 into the new block
    }

    @Test func pauseFreezesAndResumeShiftsTheEnd() async throws {
        let (service, _) = makeService()
        _ = await service.start(mode: pomodoro, goal: nil, studyScope: nil, now: start)
        await service.pause(now: start.addingTimeInterval(10 * 60))
        var status = await service.status(now: start.addingTimeInterval(10 * 60))
        #expect(status.phase == .paused)
        #expect(status.focusedSeconds == 10 * 60)

        // 20 idle minutes later: no drift while paused.
        let resumeAt = start.addingTimeInterval(30 * 60)
        _ = await service.resume(now: resumeAt)
        status = await service.status(now: resumeAt)
        #expect(status.phase == .focusing)
        // Unwrapped before comparing: #expect misresolves `Optional<Double> == Int-literal`.
        #expect(try #require(status.remaining) == 15 * 60) // the 15 minutes that were left

        // The block now ends 15 min after resume, not at the original mark.
        let events = await service.advance(now: resumeAt.addingTimeInterval(15 * 60))
        #expect(events == [.phaseStarted(.shortBreak)])
    }

    @Test func minutesGoalFiresOnceWhenFocusedTimeReachesIt() async {
        let (service, _) = makeService()
        _ = await service.start(mode: pomodoro, goal: .minutes(30), studyScope: nil, now: start)
        var events = await service.advance(now: start.addingTimeInterval(25 * 60))
        #expect(!events.contains(.goalCompleted)) // 25 focused min < 30

        // Second block passes the mark (25 + 10 = 35 focused minutes at t=40).
        events = await service.advance(now: start.addingTimeInterval(40 * 60))
        #expect(events.contains(.goalCompleted))
        events = await service.advance(now: start.addingTimeInterval(41 * 60))
        #expect(!events.contains(.goalCompleted)) // fires once
        #expect(await service.status(now: start.addingTimeInterval(40 * 60)).goalProgress == 1)
    }

    @Test func cardsGoalFiresThroughRecordCardCompleted() async {
        let (service, _) = makeService()
        _ = await service.start(mode: pomodoro, goal: .cards(2), studyScope: nil, now: start)
        #expect(await service.recordCardCompleted(now: start).isEmpty)
        #expect(await service.recordCardCompleted(now: start) == [.goalCompleted])
    }

    @Test func deepWorkIsOpenEndedAndReminds() async {
        let (service, _) = makeService()
        _ = await service.start(
            mode: .deepWork(breakReminderEvery: 50 * 60), goal: nil, studyScope: nil, now: start
        )
        #expect(await service.status(now: start).remaining == nil)
        var events = await service.advance(now: start.addingTimeInterval(49 * 60))
        #expect(events.isEmpty)
        events = await service.advance(now: start.addingTimeInterval(50 * 60))
        #expect(events == [.breakReminder])
        // Still focusing, still open-ended; focused time keeps accruing.
        let status = await service.status(now: start.addingTimeInterval(60 * 60))
        #expect(status.phase == .focusing)
        #expect(status.focusedSeconds == 60 * 60)
    }

    @Test func blockerTogglesOnFocusEdgesOnly() async {
        let (service, blocker) = makeService()
        _ = await service.start(mode: pomodoro, goal: nil, studyScope: nil, now: start)
        _ = await service.advance(now: start.addingTimeInterval(25 * 60)) // -> break
        _ = await service.advance(now: start.addingTimeInterval(30 * 60)) // -> focusing
        await service.stop(now: start.addingTimeInterval(35 * 60))
        #expect(await blocker.calls == ["on", "off", "on", "off"])
    }

    @Test func stopPersistsAFocusSessionLog() async throws {
        actor SpyLogRepository: FocusSessionLogRepository {
            private(set) var appended: [FocusSessionLog] = []
            func append(_ log: FocusSessionLog) { appended.append(log) }
            func logs(from: Date, to: Date) -> [FocusSessionLog] { appended }
        }
        let logs = SpyLogRepository()
        let service = FocusSessionService(blocker: SpyBlocker(), logRepository: logs)
        _ = await service.start(mode: pomodoro, goal: nil, studyScope: nil, now: start)
        _ = await service.recordCardCompleted(now: start)
        await service.stop(now: start.addingTimeInterval(12 * 60))

        let appended = await logs.appended
        let log = try #require(appended.first)
        #expect(appended.count == 1)
        #expect(log.startedAt == start)
        #expect(log.focusedSeconds == 12 * 60)
        #expect(log.cardsCompleted == 1)

        // A session with zero focused time leaves no row.
        _ = await service.start(mode: pomodoro, goal: nil, studyScope: nil, now: start)
        await service.pause(now: start)
        await service.stop(now: start)
        #expect(await logs.appended.count == 1)
    }

    @Test func stopAccumulatesPartialFocusTime() async {
        let (service, _) = makeService()
        _ = await service.start(mode: pomodoro, goal: nil, studyScope: nil, now: start)
        await service.stop(now: start.addingTimeInterval(7 * 60))
        let status = await service.status(now: start.addingTimeInterval(7 * 60))
        #expect(status.phase == .idle)
        #expect(status.focusedSeconds == 7 * 60)
    }
}
