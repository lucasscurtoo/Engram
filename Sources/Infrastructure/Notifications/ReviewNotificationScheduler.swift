import Foundation
import UserNotifications

/// The single daily "time to review" reminder.
///
/// One pending request at a time under a fixed identifier: every call cancels the
/// previous one first, so re-scheduling can never pile up duplicates and turning the
/// reminder off simply leaves nothing pending. A denied permission is not an error —
/// the app keeps working, just without reminders.
public actor ReviewNotificationScheduler {
    /// Fixed so a re-schedule replaces the previous request instead of adding one.
    private static let identifier = "com.engram.daily-review-reminder"

    private let notifier: LocalNotifier

    public init(notifier: LocalNotifier = LocalNotifier()) {
        self.notifier = notifier
    }

    /// Schedules (or cancels, when `enabled` is false) the daily reminder.
    /// `time` is read as hour/minute in the user's current calendar.
    public func scheduleDaily(at time: DateComponents, enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard enabled, await notifier.requestPermissionIfNeeded() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time to review"
        // macOS cannot compute the due count at delivery time, so the body is generic.
        // TODO(owner): refresh the pending notification's body with the real due count on app close.
        content.body = "You have cards to review."
        content.sound = .default

        var match = DateComponents()
        match.hour = time.hour ?? 9
        match.minute = time.minute ?? 0

        try? await center.add(
            UNNotificationRequest(
                identifier: Self.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: match, repeats: true)
            )
        )
    }
}
