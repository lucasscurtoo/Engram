import AppKit
import SwiftUI

/// Menu bar face of the focus session. Both this scene and the main window read the
/// single `FocusSessionViewModel` held by `AppDependencies`, so the countdown and the
/// controls can never drift apart.
///
/// Pattern reference: ~/Proyectos/AgenticNotch (GPL-3) — patterns only, no code.
struct MenuBarTimerLabel: View {
    let model: FocusSessionViewModel?

    var body: some View {
        if let model, model.isRunning {
            Label(model.timerText, systemImage: model.phaseSymbol)
                .accessibilityLabel("\(model.phaseTitle), \(model.timerText) remaining")
        } else {
            Image(systemName: "timer")
                .accessibilityLabel("Focus timer, no session running")
        }
    }
}

/// The dropdown: session state on top, then pause/resume + stop.
struct MenuBarTimerMenu: View {
    let model: FocusSessionViewModel?

    var body: some View {
        if let model, model.isRunning {
            Text("\(model.phaseTitle) · \(model.timerText)")
            if let detail = model.goalDetail { Text(detail) }
            Divider()
            if model.isPaused {
                Button("Resume") { Task { await model.resume() } }
            } else {
                Button("Pause") { Task { await model.pause() } }
            }
            Button("Stop") { Task { await model.stop() } }
        } else {
            Text("No focus session")
        }
        Divider()
        Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
    }
}
