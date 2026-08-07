import Application
import Foundation

/// MVP Do Not Disturb hook. macOS ships no public API to toggle a Focus filter, so
/// the supported path is a pair of user-created Shortcuts ("Recall Focus On" /
/// "Recall Focus Off") driven through the `shortcuts` CLI — see the README.
///
/// Everything here is best-effort and fire-and-forget: a missing shortcut, a missing
/// CLI, a sandbox denial or a hung shortcut must never break or stall a focus
/// session, so nothing is awaited and every failure is swallowed.
///
/// TODO(owner): SystemWideBlocker via Family Controls / Network Extension (entitlements) post-MVP.
public actor SystemFocusBlocker: DistractionBlocker {
    public static let onShortcutName = "Recall Focus On"
    public static let offShortcutName = "Recall Focus Off"

    private let timeout: TimeInterval

    /// - Parameter timeout: how long a shortcut may run before it is terminated.
    public init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    public func activate() async {
        run(Self.onShortcutName)
    }

    public func deactivate() async {
        run(Self.offShortcutName)
    }

    /// Launches the shortcut on a detached task and returns immediately, so the
    /// caller (the focus engine's actor) is never blocked by the process.
    private nonisolated func run(_ shortcut: String) {
        let timeout = timeout
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", shortcut]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            // Shortcut absent, CLI absent, sandbox denial: nothing to do about it.
            guard (try? process.run()) != nil else { return }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                try? await Task.sleep(for: .milliseconds(200))
            }
            if process.isRunning { process.terminate() }
        }
    }
}
