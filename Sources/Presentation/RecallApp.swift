import SwiftUI

enum AppInfo {
    /// Working title — rename here (and in project.yml), nowhere else.
    static let name = "Recall"
    static let quickAddWindowID = "quick-add"
}

@main
struct RecallApp: App {
    /// Built once. A failure here is shown, never swallowed.
    private let dependencies: Result<AppDependencies, Error>

    init() {
        dependencies = Result { try AppDependencies() }
    }

    /// nil only when the store failed to open (the app shows `StartupErrorView`).
    @MainActor private var focus: FocusSessionViewModel? {
        if case .success(let dependencies) = dependencies { dependencies.focus } else { nil }
    }

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            switch dependencies {
            case .success(let dependencies):
                ContentView(dependencies: dependencies)
                    .environment(dependencies)
            case .failure(let error):
                StartupErrorView(error: error)
            }
        }
        .commands {
            CommandMenu("Notes") {
                QuickAddCommand()
            }
        }

        // Utility window for Quick Add; opened from the Notes menu (Cmd+Shift+N).
        Window("Quick Add", id: AppInfo.quickAddWindowID) {
            if case .success(let dependencies) = dependencies {
                QuickAddView()
                    .environment(dependencies)
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 520)

        // Always-visible focus timer; live countdown while a session runs.
        MenuBarExtra {
            MenuBarTimerMenu(model: focus)
        } label: {
            MenuBarTimerLabel(model: focus)
        }
    }
}

/// Split out so it can own `openWindow`, which `App` bodies cannot read directly.
private struct QuickAddCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Quick Add") { openWindow(id: AppInfo.quickAddWindowID) }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        // TODO(owner): system-wide global hotkey (post-MVP)
    }
}

struct ContentView: View {
    let dependencies: AppDependencies

    @State private var decks: DeckListViewModel
    @State private var selection: AppRoute?
    @State private var launcher = StudyLauncher()
    /// Collapsed while a focus session runs — the running screen owns the window.
    @State private var columns = NavigationSplitViewVisibility.automatic

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _decks = State(initialValue: DeckListViewModel(deckService: dependencies.deckService))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            DeckListView(model: decks, selection: $selection)
        } detail: {
            switch selection {
            case .deck(let id):
                if let summary = decks.summary(for: id) {
                    DeckDetailView(summary: summary, decks: decks.decks) {
                        await decks.load()
                    }
                    .id(id)
                } else {
                    ContentUnavailableView("Deck not found", systemImage: "questionmark.folder")
                }
            case .stats:
                StatsView()
            case .focus:
                FocusSessionView(model: dependencies.focus, decks: decks.decks)
            case nil:
                ContentUnavailableView(
                    "Select a deck to get started", systemImage: "rectangle.stack"
                )
            }
        }
        .environment(launcher)
        // Dedicated review screen: a sheet covers the sidebar without a second window.
        .sheet(item: $launcher.scope, onDismiss: { Task { await decks.load() } }) { scope in
            ReviewSessionView(scope: scope, dependencies: dependencies)
        }
        .onChange(of: dependencies.focus.isRunning) { _, isRunning in
            columns = isRunning ? .detailOnly : .automatic
        }
        .task { await decks.load() }
    }
}

/// Shown instead of the app when the store cannot be opened.
struct StartupErrorView: View {
    let error: Error

    var body: some View {
        ContentUnavailableView {
            Label("\(AppInfo.name) could not open its library", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        }
        .frame(minWidth: 420, minHeight: 260)
    }
}
