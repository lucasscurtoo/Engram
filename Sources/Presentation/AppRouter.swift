import Foundation

/// Sidebar destinations. Drives the detail column in `ContentView`.
enum AppRoute: Hashable {
    case deck(UUID)
    case stats
    case focus
}
