import Foundation
import Domain

/// Timer structure for a focus session.
public enum FocusMode: Sendable, Hashable {
    case pomodoro(PomodoroConfig)
    /// Long continuous block; optional break reminder cadence.
    case deepWork(breakReminderEvery: TimeInterval?)
}

public struct PomodoroConfig: Sendable, Codable, Hashable {
    public var work: TimeInterval
    public var shortBreak: TimeInterval
    public var longBreak: TimeInterval
    public var cyclesPerLongBreak: Int

    public init(
        work: TimeInterval = 25 * 60, shortBreak: TimeInterval = 5 * 60,
        longBreak: TimeInterval = 15 * 60, cyclesPerLongBreak: Int = 4
    ) {
        self.work = work
        self.shortBreak = shortBreak
        self.longBreak = longBreak
        self.cyclesPerLongBreak = cyclesPerLongBreak
    }
}

public enum FocusPhase: Sendable, Hashable {
    case idle
    case focusing
    case shortBreak
    case longBreak
    case paused
}

/// Session goal with progress feedback.
public enum FocusGoal: Sendable, Hashable {
    case minutes(Int)
    case cards(Int)
}

/// Emitted by `start`/`advance`/`resume` so the UI can schedule notifications
/// and update the menu bar without polling internals.
public enum FocusEvent: Sendable, Hashable {
    case phaseStarted(FocusPhase)
    case breakReminder
    case goalCompleted
}

/// Snapshot for rendering. Everything is a function of the session state + `now`.
public struct FocusStatus: Sendable, Hashable {
    public let phase: FocusPhase
    /// nil = open-ended (deep work or idle). While paused this is the frozen
    /// remainder of the interrupted phase, so progress UIs keep their state.
    public let remaining: TimeInterval?
    /// Full length of the current (or paused) phase; nil when open-ended.
    public let phaseDuration: TimeInterval?
    /// Pomodoro only: work blocks per long-break round.
    public let cyclesPerLongBreak: Int?
    /// Total focused time this session, current block included.
    public let focusedSeconds: TimeInterval
    /// Finished pomodoro work blocks.
    public let completedFocusBlocks: Int
    public let cardsCompleted: Int
    public let goal: FocusGoal?
    /// 0...1, nil when no goal is set.
    public var goalProgress: Double? {
        switch goal {
        case nil: nil
        case .minutes(let m): min(1, focusedSeconds / (Double(m) * 60))
        case .cards(let c): min(1, Double(cardsCompleted) / Double(max(1, c)))
        }
    }
}

/// Focus engine (M5 core). Wall-clock based: no internal timers — the UI drives it
/// by calling `advance(now:)` on its own tick, so the machine is deterministic,
/// fully testable, and survives app sleep (missed transitions are caught up).
/// Wraps an optional study scope; study and focus share the same screen (UI's job).
public actor FocusSessionService {
    private let blocker: any DistractionBlocker
    /// When present, every finished session is appended here for stats (best-effort).
    private let logRepository: (any FocusSessionLogRepository)?

    public private(set) var mode: FocusMode?
    public private(set) var goal: FocusGoal?
    /// Deck/tag hooked into `focusing` blocks; UI reads it to embed the study queue.
    public private(set) var studyScope: StudyScope?

    private var phase: FocusPhase = .idle
    private var phaseStartedAt = Date.distantPast
    private var phaseEndsAt: Date?
    /// Focused seconds from finished blocks/segments (running segment excluded).
    private var focusedAccumulated: TimeInterval = 0
    private var completedFocusBlocks = 0
    private var cardsCompleted = 0
    private var goalFired = false
    /// Pause bookkeeping: what to go back to and how much of it was left.
    private var pausedPhase: FocusPhase?
    private var pausedRemaining: TimeInterval?
    /// Deep work only.
    private var nextReminderAt: Date?
    private var sessionStartedAt: Date?

    public init(
        blocker: any DistractionBlocker,
        logRepository: (any FocusSessionLogRepository)? = nil
    ) {
        self.blocker = blocker
        self.logRepository = logRepository
    }

    // MARK: - Lifecycle

    public func start(
        mode: FocusMode, goal: FocusGoal?, studyScope: StudyScope?, now: Date
    ) async -> [FocusEvent] {
        self.mode = mode
        self.goal = goal
        self.studyScope = studyScope
        focusedAccumulated = 0
        completedFocusBlocks = 0
        cardsCompleted = 0
        goalFired = false
        pausedPhase = nil
        pausedRemaining = nil
        sessionStartedAt = now
        await enter(.focusing, now: now)
        return [.phaseStarted(.focusing)]
    }

    /// Call on every UI tick. Processes all transitions due since the last call —
    /// if the Mac slept through a whole break, the machine catches up instead of stalling.
    public func advance(now: Date) async -> [FocusEvent] {
        var events: [FocusEvent] = []
        while let endsAt = phaseEndsAt, now >= endsAt {
            switch phase {
            case .focusing:
                focusedAccumulated += endsAt.timeIntervalSince(phaseStartedAt)
                completedFocusBlocks += 1
                let next: FocusPhase =
                    if case .pomodoro(let config) = mode,
                       completedFocusBlocks % max(1, config.cyclesPerLongBreak) == 0 {
                        .longBreak
                    } else {
                        .shortBreak
                    }
                await enter(next, at: endsAt)
                events.append(.phaseStarted(next))
            case .shortBreak, .longBreak:
                await enter(.focusing, at: endsAt)
                events.append(.phaseStarted(.focusing))
            case .idle, .paused:
                phaseEndsAt = nil // unreachable; defensive
            }
        }
        if phase == .focusing, let reminderAt = nextReminderAt, now >= reminderAt,
           case .deepWork(.some(let every)) = mode {
            events.append(.breakReminder)
            nextReminderAt = reminderAt.addingTimeInterval(every)
        }
        events.append(contentsOf: checkGoal(now: now))
        return events
    }

    public func pause(now: Date) async {
        guard phase == .focusing || phase == .shortBreak || phase == .longBreak else { return }
        if phase == .focusing {
            focusedAccumulated += now.timeIntervalSince(phaseStartedAt)
            await blocker.deactivate()
        }
        pausedPhase = phase
        pausedRemaining = phaseEndsAt.map { max(0, $0.timeIntervalSince(now)) }
        phase = .paused
        phaseEndsAt = nil
    }

    public func resume(now: Date) async -> [FocusEvent] {
        guard phase == .paused, let resumed = pausedPhase else { return [] }
        phase = resumed
        phaseStartedAt = now
        phaseEndsAt = pausedRemaining.map { now.addingTimeInterval($0) }
        pausedPhase = nil
        pausedRemaining = nil
        if resumed == .focusing { await blocker.activate() }
        return [.phaseStarted(resumed)]
    }

    public func stop(now: Date) async {
        if phase == .focusing {
            focusedAccumulated += now.timeIntervalSince(phaseStartedAt)
            await blocker.deactivate()
        }
        phase = .idle
        phaseEndsAt = nil
        pausedPhase = nil
        pausedRemaining = nil
        nextReminderAt = nil
        if let startedAt = sessionStartedAt, focusedAccumulated > 0 {
            // Best-effort: losing a stats row must never break session teardown.
            try? await logRepository?.append(FocusSessionLog(
                startedAt: startedAt, endedAt: now,
                focusedSeconds: focusedAccumulated,
                completedFocusBlocks: completedFocusBlocks,
                cardsCompleted: cardsCompleted
            ))
        }
        sessionStartedAt = nil
    }

    /// UI reports each card graded while focusing, for `.cards` goals and stats.
    public func recordCardCompleted(now: Date) -> [FocusEvent] {
        cardsCompleted += 1
        return checkGoal(now: now)
    }

    public func status(now: Date) -> FocusStatus {
        FocusStatus(
            phase: phase,
            remaining: phaseEndsAt.map { max(0, $0.timeIntervalSince(now)) } ?? pausedRemaining,
            phaseDuration: currentPhaseDuration,
            cyclesPerLongBreak: {
                guard case .pomodoro(let config) = mode else { return nil }
                return config.cyclesPerLongBreak
            }(),
            focusedSeconds: focusedSeconds(now: now),
            completedFocusBlocks: completedFocusBlocks,
            cardsCompleted: cardsCompleted,
            goal: goal
        )
    }

    private var currentPhaseDuration: TimeInterval? {
        guard case .pomodoro(let config) = mode else { return nil }
        let effective = phase == .paused ? pausedPhase : phase
        return switch effective {
        case .focusing: config.work
        case .shortBreak: config.shortBreak
        case .longBreak: config.longBreak
        case .idle, .paused, nil: nil
        }
    }

    // MARK: - Private

    /// Enter a phase "now" (user action) — blocker toggles on the focusing edge.
    private func enter(_ newPhase: FocusPhase, now: Date) async {
        await enter(newPhase, at: now)
    }

    /// Enter a phase at a specific instant (possibly in the past during catch-up).
    private func enter(_ newPhase: FocusPhase, at instant: Date) async {
        let wasFocusing = phase == .focusing
        phase = newPhase
        phaseStartedAt = instant
        switch mode {
        case .pomodoro(let config):
            let duration: TimeInterval = switch newPhase {
            case .focusing: config.work
            case .shortBreak: config.shortBreak
            case .longBreak: config.longBreak
            case .idle, .paused: 0
            }
            phaseEndsAt = duration > 0 ? instant.addingTimeInterval(duration) : nil
        case .deepWork(let reminder):
            phaseEndsAt = nil // open-ended
            nextReminderAt = reminder.map { instant.addingTimeInterval($0) }
        case nil:
            phaseEndsAt = nil
        }
        if newPhase == .focusing, !wasFocusing {
            await blocker.activate()
        } else if newPhase != .focusing, wasFocusing {
            await blocker.deactivate()
        }
    }

    private func focusedSeconds(now: Date) -> TimeInterval {
        guard phase == .focusing else { return focusedAccumulated }
        let segmentEnd = phaseEndsAt.map { min(now, $0) } ?? now
        return focusedAccumulated + max(0, segmentEnd.timeIntervalSince(phaseStartedAt))
    }

    private func checkGoal(now: Date) -> [FocusEvent] {
        guard !goalFired, let progress = status(now: now).goalProgress, progress >= 1 else { return [] }
        goalFired = true
        return [.goalCompleted]
    }
}
