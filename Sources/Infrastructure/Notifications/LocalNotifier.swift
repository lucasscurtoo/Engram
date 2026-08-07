import Foundation
import UserNotifications

/// Thin `UserNotifications` wrapper for immediate, local-only alerts (focus block
/// ends, break reminders, goal reached).
///
/// Permission is asked once, lazily, and a denial is final and silent: notifications
/// are a nicety on top of a focus session, never a precondition for one.
public actor LocalNotifier {
    /// nil = not asked yet.
    private var isAuthorized: Bool?

    public init() {}

    public func requestPermissionIfNeeded() async {
        guard isAuthorized == nil else { return }
        let center = UNUserNotificationCenter.current()
        if let settings = await center.notificationSettings() as UNNotificationSettings?,
           settings.authorizationStatus == .denied {
            isAuthorized = false
            return
        }
        isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    public func notify(title: String, body: String) async {
        await requestPermissionIfNeeded()
        guard isAuthorized == true else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
