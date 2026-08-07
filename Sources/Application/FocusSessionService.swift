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

/// Session/day goal with progress feedback.
public enum FocusGoal: Sendable, Hashable {
    case minutes(Int)
    case cards(Int)
}

/// Focus engine (M5): wraps an optional StudySession during `focusing` blocks.
/// Pillar of the product — study and focus share the same screen.
///
/// TODO(owner): M5 — implement:
///  - timer loop driving FocusPhase transitions (pomodoro cycles / deep work)
///  - activate()/deactivate() the DistractionBlocker on focusing enter/exit
///  - AmbienceController play/stop tied to focusing
///  - goal progress tracking (minutes elapsed / cards completed via StudySession)
///  - block-end notifications + menu bar timer publishing
///  - persist a FocusSessionLog for stats (see StatsService TODO)
public actor FocusSessionService {
    public private(set) var phase: FocusPhase = .idle

    private let blocker: any DistractionBlocker
    private let ambience: any AmbienceController

    public init(blocker: any DistractionBlocker, ambience: any AmbienceController) {
        self.blocker = blocker
        self.ambience = ambience
    }

    public func start(mode: FocusMode, goal: FocusGoal?, studyScope: StudyScope?) async {
        // TODO(owner): M5
    }

    public func pause() async {
        // TODO(owner): M5
    }

    public func resume() async {
        // TODO(owner): M5
    }

    public func stop() async {
        // TODO(owner): M5
    }
}
