import Application
import Domain
import Foundation
import Infrastructure

extension AmbienceTrack {
    var label: String {
        switch self {
        case .rain: "Rain"
        case .whiteNoise: "White noise"
        case .cafe: "Café"
        }
    }
}

/// @Observable face of `FocusSessionService`. The engine is wall-clock based and has
/// no timers of its own, so this view model is what makes it move: a 1 s loop calling
/// `advance` + `status`, plus the side effects the engine deliberately does not own
/// (notifications and ambient audio). Distraction blocking is *not* here — the engine
/// drives `DistractionBlocker` itself on the focusing edges.
///
/// One instance lives on `AppDependencies` so the main window and the menu bar
/// observe the same session.
@MainActor
@Observable
final class FocusSessionViewModel {
    enum ModeKind: String, CaseIterable, Identifiable {
        case pomodoro, deepWork
        var id: String { rawValue }
        var label: String { self == .pomodoro ? "Pomodoro" : "Deep Work" }
    }

    enum GoalKind: String, CaseIterable, Identifiable {
        case none, minutes, cards
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: "No goal"
            case .minutes: "Minutes"
            case .cards: "Cards"
            }
        }
    }

    enum AttachmentKind: String, CaseIterable, Identifiable {
        case none, deck, tag
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: "Just the timer"
            case .deck: "Study a deck"
            case .tag: "Study a tag"
            }
        }
    }

    // MARK: - Setup state

    var modeKind: ModeKind = .pomodoro
    var workMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var cyclesPerLongBreak = 4
    var breakReminderEnabled = true
    var breakReminderMinutes = 50

    var goalKind: GoalKind = .none
    var goalMinutes = 50
    var goalCards = 30

    var attachmentKind: AttachmentKind = .none
    var deckID: UUID?
    var tag = ""

    var ambienceEnabled = false
    var ambienceTrack: AmbienceTrack = .rain
    var ambienceVolume = 0.5

    // MARK: - Session state

    /// nil until a session starts (`FocusStatus` has no public initializer).
    private(set) var status: FocusStatus?
    /// True from `start()` until `stop()`, breaks and pauses included.
    private(set) var isRunning = false
    private(set) var goalReached = false
    /// Last finished session, shown as the completion screen until dismissed.
    private(set) var finished: FocusStatus?
    /// The embedded study flow, when the session was started with a scope.
    private(set) var review: ReviewSessionViewModel?

    private unowned let dependencies: AppDependencies
    private let session: FocusSessionService
    private let ambience = AudioAmbienceController()
    private let notifier = LocalNotifier()
    private var ticker: Task<Void, Never>?

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        session = FocusSessionService(
            blocker: dependencies.focusBlocker,
            logRepository: dependencies.focusLogRepository
        )
    }

    // MARK: - Derived

    var phase: FocusPhase { status?.phase ?? .idle }
    var isPaused: Bool { phase == .paused }
    var isFocusing: Bool { phase == .focusing }
    var isOnBreak: Bool { phase == .shortBreak || phase == .longBreak }
    /// Deep work: the block never ends on its own, so the timer counts up.
    var isOpenEnded: Bool { isRunning && status?.remaining == nil }

    var availableAmbienceTracks: [AmbienceTrack] { AudioAmbienceController.availableTracks() }

    var phaseTitle: String {
        switch phase {
        case .idle: "Idle"
        case .focusing: modeKind == .pomodoro ? "Focus" : "Deep work"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        case .paused: "Paused"
        }
    }

    var phaseSymbol: String {
        switch phase {
        case .idle: "timer"
        case .focusing: "brain.head.profile"
        case .shortBreak: "cup.and.saucer"
        case .longBreak: "figure.walk"
        case .paused: "pause.circle"
        }
    }

    /// Remaining time, or elapsed focused time when the block is open-ended.
    var timerText: String {
        guard let status else { return "--:--" }
        return Self.clock(status.remaining ?? status.focusedSeconds)
    }

    var goalProgress: Double? { status?.goalProgress }

    var goalDetail: String? {
        guard let status, let goal = status.goal else { return nil }
        return switch goal {
        case .minutes(let target): "\(Int(status.focusedSeconds / 60)) / \(target) min focused"
        case .cards(let target): "\(status.cardsCompleted) / \(target) cards"
        }
    }

    var sessionSummary: String {
        guard let finished else { return "" }
        let minutes = Int((finished.focusedSeconds / 60).rounded())
        return "\(minutes) min focused · \(finished.completedFocusBlocks) blocks · \(finished.cardsCompleted) cards"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.rounded()))
        return total >= 3_600
            ? String(format: "%d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Lifecycle

    func start() async {
        guard !isRunning else { return }
        await notifier.requestPermissionIfNeeded()
        finished = nil
        goalReached = false
        let scope = resolvedScope
        review = scope.map {
            ReviewSessionViewModel(scope: $0, session: dependencies.makeReviewSession())
        }
        isRunning = true
        // The opening block is not announced — the user just pressed Start.
        await apply(await session.start(
            mode: resolvedMode, goal: resolvedGoal, studyScope: scope, now: .now
        ), announce: false)
        await refresh()
        startTicking()
    }

    func pause() async {
        await session.pause(now: .now)
        await refresh()
    }

    func resume() async {
        await apply(await session.resume(now: .now), announce: false)
        await refresh()
    }

    func stop() async {
        ticker?.cancel()
        ticker = nil
        let last = await session.status(now: .now)
        await session.stop(now: .now)
        await ambience.stop()
        finished = last
        status = nil
        review = nil
        isRunning = false
    }

    /// Clears the completion screen and returns to setup.
    func dismissSummary() {
        finished = nil
        goalReached = false
    }

    /// Reported by the embedded study flow after every grade (drives `.cards` goals).
    func recordCardGraded() async {
        guard isRunning else { return }
        await apply(await session.recordCardCompleted(now: .now))
        await refresh()
    }

    /// One engine tick. The engine is catch-up safe, so a missed tick (sleep, stall)
    /// costs nothing — the next one replays every transition that came due.
    func tick() async {
        guard isRunning else { return }
        await apply(await session.advance(now: .now))
        await refresh()
    }

    func ambienceSettingsChanged() async {
        await syncAmbience()
    }

    // MARK: - Private

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                await tick()
            }
        }
    }

    private func refresh() async {
        status = await session.status(now: .now)
        await syncAmbience()
    }

    /// ponytail: called every tick and idempotent — `play` on the same, already
    /// playing asset is a no-op, which is cheaper than tracking audio state twice.
    private func syncAmbience() async {
        guard ambienceEnabled, isFocusing, AudioAmbienceController.isAvailable(ambienceTrack.assetName)
        else { return await ambience.stop() }
        await ambience.play(ambienceTrack, volume: ambienceVolume)
    }

    private func apply(_ events: [FocusEvent], announce: Bool = true) async {
        for event in events {
            switch event {
            case .phaseStarted(.focusing):
                if announce {
                    await notifier.notify(title: "Back to focus", body: "Your next block has started.")
                }
            case .phaseStarted(.shortBreak), .phaseStarted(.longBreak):
                if announce {
                    await notifier.notify(title: "Break time", body: "Step away for a moment.")
                }
            case .phaseStarted:
                break
            case .breakReminder:
                await notifier.notify(
                    title: "Time for a break", body: "You have been focusing for a while."
                )
            case .goalCompleted:
                goalReached = true
                await notifier.notify(title: "Goal reached", body: goalDetail ?? "Nice work.")
            }
        }
    }

    private var resolvedMode: FocusMode {
        switch modeKind {
        case .pomodoro:
            .pomodoro(PomodoroConfig(
                work: Double(max(1, workMinutes)) * 60,
                shortBreak: Double(max(1, shortBreakMinutes)) * 60,
                longBreak: Double(max(1, longBreakMinutes)) * 60,
                cyclesPerLongBreak: max(1, cyclesPerLongBreak)
            ))
        case .deepWork:
            .deepWork(
                breakReminderEvery: breakReminderEnabled
                    ? Double(max(1, breakReminderMinutes)) * 60
                    : nil
            )
        }
    }

    private var resolvedGoal: FocusGoal? {
        switch goalKind {
        case .none: nil
        case .minutes: .minutes(max(1, goalMinutes))
        case .cards: .cards(max(1, goalCards))
        }
    }

    private var resolvedScope: StudyScope? {
        switch attachmentKind {
        case .none: nil
        case .deck: deckID.map(StudyScope.deck)
        case .tag:
            tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : .tag(tag.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
