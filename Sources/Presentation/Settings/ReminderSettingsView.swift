import Infrastructure
import SwiftUI

/// The app's Settings scene (Cmd+,). One preference so far: the daily review
/// reminder. `@AppStorage` is the source of truth; every change re-schedules, and
/// switching the toggle off cancels the pending notification.
struct ReminderSettingsView: View {
    @AppStorage("reminder.enabled") private var isEnabled = false
    @AppStorage("reminder.hour") private var hour = 9
    @AppStorage("reminder.minute") private var minute = 0

    let scheduler: ReviewNotificationScheduler

    var body: some View {
        Form {
            Section {
                Toggle("Daily review reminder", isOn: $isEnabled)
                DatePicker("Remind me at", selection: time, displayedComponents: .hourAndMinute)
                    .disabled(!isEnabled)
            } footer: {
                Text("If macOS notifications are turned off for \(AppInfo.name), reminders are skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        // Re-applied whenever Settings opens, so a permission granted later takes effect.
        .task { await apply() }
        .onChange(of: isEnabled) { Task { await apply() } }
        .onChange(of: hour) { Task { await apply() } }
        .onChange(of: minute) { Task { await apply() } }
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                hour = components.hour ?? hour
                minute = components.minute ?? minute
            }
        )
    }

    private func apply() async {
        await scheduler.scheduleDaily(
            at: DateComponents(hour: hour, minute: minute), enabled: isEnabled
        )
    }
}
