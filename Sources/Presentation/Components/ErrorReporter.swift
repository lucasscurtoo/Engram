import Foundation
import SwiftUI

/// The app's single error surface. Presentation never swallows a thrown error:
/// every `catch` in a view or view model ends here, and one alert per window
/// (`.errorAlert(_:)`) shows it.
///
/// Scope: transient failures of an action the user just triggered (a save, a
/// delete, a reload). A screen that cannot load its *content* at all keeps
/// rendering that as an inline unavailable state instead — the review header and
/// `StatsView` do this — because an alert over an empty screen says less.
@MainActor
@Observable
final class ErrorReporter {
    private(set) var message: String?

    func report(_ error: Error) {
        message = error.localizedDescription
    }

    func dismiss() {
        message = nil
    }

    /// Runs `work`, surfacing anything it throws. The one call shape every write
    /// in Presentation uses, so no site has to remember to handle failure.
    func run(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            report(error)
        }
    }

    /// Same, for reads with a usable fallback: reports the failure *and* keeps the
    /// screen honest by returning `fallback` instead of a silent empty result.
    func value<T>(_ work: () async throws -> T, fallback: T) async -> T {
        do {
            return try await work()
        } catch {
            report(error)
            return fallback
        }
    }
}

extension View {
    /// Attach once per window (the main window and Quick Add). Sheets dismiss before
    /// their write lands, so the alert always belongs to the window underneath.
    func errorAlert(_ reporter: ErrorReporter) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(
                get: { reporter.message != nil },
                set: { if !$0 { reporter.dismiss() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reporter.message ?? "")
        }
    }
}
