import SwiftUI

/// TODO(owner): M4 — review flow: front → "Show answer" → back + 4 rating buttons
/// with previewIntervals. Mandatory shortcuts: Space = show answer, 1-4 = ratings.
/// Renders sides via FieldContentView over noteType.frontFields/backFields — never
/// a raw card field. Ends with a session summary screen.
struct ReviewSessionView: View {
    var body: some View {
        Text("Review session — M4")
            .foregroundStyle(.secondary)
    }
}
