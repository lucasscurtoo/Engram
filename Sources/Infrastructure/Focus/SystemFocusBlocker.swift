import Domain

// TODO(owner): M5 — implement DistractionBlocker (Sources/Application/Focus):
// trigger macOS Do Not Disturb / Focus on activate(), restore on deactivate(),
// using the available native path (Focus filter / notification silencing).
// If the OS refuses without permission, degrade gracefully — never break the session.
// TODO(owner): SystemWideBlocker (app/web blocking, Family Controls / Network
// Extension entitlements) is post-MVP — a second implementation of the same protocol.
