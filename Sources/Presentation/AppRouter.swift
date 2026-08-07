import Foundation

/// Sidebar destinations. Drives the detail column in `ContentView`.
enum AppRoute: Hashable {
    case deck(UUID)
    /// Placeholder until M6.
    case stats
    /// Placeholder until M5.
    case focus
}
