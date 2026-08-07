import Foundation

/// Focus seam: the MVP implementation (`SystemFocusBlocker` in Infrastructure) only
/// triggers macOS Do Not Disturb / Focus and must degrade gracefully without permission.
/// TODO(owner): SystemWideBlocker (apps/websites via Family Controls / Network
/// Extension, needs Apple entitlements) is post-MVP and plugs in as another
/// implementation of this same protocol.
public protocol DistractionBlocker: Sendable {
    func activate() async
    func deactivate() async
}
