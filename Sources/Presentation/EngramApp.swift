import SwiftUI

enum AppInfo {
    /// Working title — rename here (and in project.yml), nowhere else.
    static let name = "Engram"
    static let quickAddWindowID = "quick-add"
}

@main
struct EngramApp: App {
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
                    .uiZoom()
            case .failure(let error):
                StartupErrorView(error: error)
            }
        }
        // No title band: the design draws its own chrome, and in full screen the
        // stock titlebar strip reads as a glitch between the two toolbars.
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Lands in the standard View menu, next to Show/Hide Sidebar.
            CommandGroup(after: .sidebar) {
                Divider()
                ZoomCommands()
            }
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

        Settings {
            if case .success(let dependencies) = dependencies {
                ReminderSettingsView(scheduler: dependencies.reviewNotificationScheduler)
            }
        }

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
    /// Hidden while a focus session runs — the running screen owns the window.
    @State private var showSidebar = true

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _decks = State(initialValue: DeckListViewModel(
            deckService: dependencies.deckService, errors: dependencies.errors
        ))
    }

    var body: some View {
        // A plain flat sidebar (Notion-style), not NavigationSplitView: its macOS
        // treatment floats the sidebar as an inset rounded pane and that cannot be
        // turned off. One HStack, one hairline, edge to edge.
        HStack(spacing: 0) {
            if showSidebar {
                DeckListView(model: decks, selection: $selection)
                    .frame(width: 240)
                    .transition(.move(edge: .leading))
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: Theme.hairlineWidth)
                    .ignoresSafeArea()
            }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WindowBackground())
        .background(Theme.bg0.ignoresSafeArea())
        .environment(launcher)
        // Dedicated review screen: a sheet covers the sidebar without a second window.
        .sheet(item: $launcher.request, onDismiss: { Task { await decks.load() } }) { request in
            ReviewSessionView(request: request, dependencies: dependencies)
        }
        .onChange(of: dependencies.focus.isRunning) { _, isRunning in
            withAnimation(.easeOut(duration: 0.2)) { showSidebar = !isRunning }
        }
        .errorAlert(dependencies.errors)
        .task { await decks.load() }
    }

    @ViewBuilder
    private var detail: some View {
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
                    "No deck selected",
                    systemImage: "rectangle.stack",
                    description: Text("Pick a deck in the sidebar to browse or study its cards.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg0)
            }
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
