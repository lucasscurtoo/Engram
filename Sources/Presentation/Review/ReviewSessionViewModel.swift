import Application
import Domain
import Foundation

/// @Observable wrapper over one `StudySession` actor — review or cram, the protocol
/// covers everything this model calls.
/// Owns nothing but presentation state — the queue, FSRS and persistence stay in the actor.
@MainActor
@Observable
final class ReviewSessionViewModel {
    private(set) var item: StudyItem?
    private(set) var progress = StudyProgress()
    private(set) var intervals: [Rating: TimeInterval] = [:]
    private(set) var isLoading = true
    /// Seconds between `start()` and the queue emptying (frozen once finished).
    private(set) var elapsed: TimeInterval = 0
    private(set) var errorMessage: String?
    /// Grades this session can still take back. Reset by `start`, +1 per grade, -1 per undo.
    private(set) var undoCount = 0
    var revealed = false

    private let scope: StudyScope
    private let session: any StudySession
    private var startedAt = Date.now

    /// The session is created per instance — the actor holds the queue state.
    init(scope: StudyScope, session: any StudySession) {
        self.scope = scope
        self.session = session
    }

    /// True once the queue has run dry after at least one grade.
    var isFinished: Bool { !isLoading && item == nil && progress.completed > 0 }
    /// True when the session started with nothing to study.
    var isEmpty: Bool { !isLoading && item == nil && progress.completed == 0 }

    var correctPercentage: Int {
        progress.completed == 0 ? 0 : Int((Double(progress.correct) / Double(progress.completed) * 100).rounded())
    }

    var elapsedMinutes: Int { max(0, Int((elapsed / 60).rounded())) }

    var canUndo: Bool { undoCount > 0 }

    func start() async {
        guard isLoading else { return } // `.task` can re-fire; the queue is built once.
        startedAt = .now
        undoCount = 0
        do {
            try await session.start(scope: scope, now: startedAt)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        await refresh()
    }

    func grade(_ rating: Rating) async {
        guard item != nil else { return }
        do {
            try await session.grade(rating, now: .now)
            undoCount += 1
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
    }

    /// Puts the last graded card back, answer showing: the user was looking at the
    /// side they just graded and expects to land exactly there.
    func undo() async {
        do {
            guard try await session.undoLast() else { return }
            undoCount = max(0, undoCount - 1)
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()
        revealed = true
    }

    /// Empty in modes without scheduling (cram) — the rating buttons drop the caption.
    var showsIntervals: Bool { !intervals.isEmpty }

    func intervalLabel(for rating: Rating) -> String {
        guard showsIntervals else { return "" }
        return intervals[rating].map(Self.intervalLabel) ?? "—"
    }

    /// Compact interval label, used only on the four rating buttons.
    static func intervalLabel(_ interval: TimeInterval) -> String {
        switch interval {
        case ..<60: "<1 min"
        case ..<3_600: "\(Int((interval / 60).rounded())) min"
        case ..<86_400: "\(Int((interval / 3_600).rounded())) h"
        case ..<(30 * 86_400): "\(Int((interval / 86_400).rounded())) d"
        default: String(format: "%.1f mo", interval / (30 * 86_400))
        }
    }

    private func refresh(now: Date = .now) async {
        item = await session.currentItem
        progress = await session.progress
        intervals = item == nil ? [:] : await session.previewIntervals(now: now)
        revealed = false
        if item == nil { elapsed = now.timeIntervalSince(startedAt) }
    }
}
