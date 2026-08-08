import AppKit
import Infrastructure
import SwiftUI

/// The system sounds a focus chime can use. "None" silences that transition.
enum ChimeSound {
    static let none = "None"
    static let all = [
        none, "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    static func play(_ name: String) {
        guard name != none else { return }
        NSSound(named: name)?.play()
    }
}

/// The app's Settings scene (Cmd+,). One preference so far: the daily review
/// reminder. `@AppStorage` is the source of truth; every change re-schedules, and
/// switching the toggle off cancels the pending notification.
struct ReminderSettingsView: View {
    @AppStorage("reminder.enabled") private var isEnabled = false
    @AppStorage("reminder.hour") private var hour = 9
    @AppStorage("reminder.minute") private var minute = 0
    @AppStorage("sound.breakStart") private var breakSound = "Glass"
    @AppStorage("sound.focusStart") private var focusSound = "Ping"

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
            Section("Focus sounds") {
                Picker("Break starts", selection: $breakSound) {
                    ForEach(ChimeSound.all, id: \.self) { Text($0).tag($0) }
                }
                Picker("Back to focus", selection: $focusSound) {
                    ForEach(ChimeSound.all, id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380)
        // Re-applied whenever Settings opens, so a permission granted later takes effect.
        .task { await apply() }
        .onChange(of: isEnabled) { Task { await apply() } }
        .onChange(of: hour) { Task { await apply() } }
        .onChange(of: minute) { Task { await apply() } }
        // Instant preview: hear the pick right away.
        .onChange(of: breakSound) { _, sound in ChimeSound.play(sound) }
        .onChange(of: focusSound) { _, sound in ChimeSound.play(sound) }
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
