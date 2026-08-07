import Foundation

/// Sidebar destinations. TODO(owner): M3 — wire selection state into ContentView.
enum AppRoute: Hashable {
    case deck(UUID)
    case stats
    case focus
}
