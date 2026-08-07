import Application
import Domain
import SwiftUI

/// Focus mode, two states in one screen.
///
/// Setup is an ordinary form. Running is deliberately bare: the sidebar collapses
/// (`ContentView`), the toolbar is gone, and all that is left is the timer, the phase,
/// the goal bar and — when the session carries a study scope — the same card UI the
/// review screen uses (`StudyCardView`), so studying happens *inside* the block.
struct FocusSessionView: View {
    @Bindable var model: FocusSessionViewModel
    /// For the deck picker in setup.
    let decks: [Deck]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.isRunning {
                running
            } else if model.finished != nil {
                completion
            } else {
                setup
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Setup

    private var setup: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $model.modeKind) {
                    ForEach(FocusSessionViewModel.ModeKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if model.modeKind == .pomodoro {
                    minutes("Work", value: $model.workMinutes, range: 1...180)
                    minutes("Short break", value: $model.shortBreakMinutes, range: 1...60)
                    minutes("Long break", value: $model.longBreakMinutes, range: 1...90)
                    Stepper(
                        "Blocks before a long break: \(model.cyclesPerLongBreak)",
                        value: $model.cyclesPerLongBreak, in: 1...12
                    )
                } else {
                    Toggle("Remind me to take breaks", isOn: $model.breakReminderEnabled)
                    if model.breakReminderEnabled {
                        minutes("Every", value: $model.breakReminderMinutes, range: 5...240)
                    }
                }
            }

            Section("Goal") {
                Picker("Goal", selection: $model.goalKind) {
                    ForEach(FocusSessionViewModel.GoalKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch model.goalKind {
                case .none: EmptyView()
                case .minutes: minutes("Focus for", value: $model.goalMinutes, range: 5...600)
                case .cards: Stepper("Review \(model.goalCards) cards", value: $model.goalCards, in: 1...500)
                }
            }

            Section("Study") {
                Picker("Study", selection: $model.attachmentKind) {
                    ForEach(FocusSessionViewModel.AttachmentKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch model.attachmentKind {
                case .none:
                    EmptyView()
                case .deck:
                    Picker("Deck", selection: $model.deckID) {
                        Text("Select a deck").tag(UUID?.none)
                        ForEach(decks, id: \.id) { deck in
                            Text(DeckTree.fullName(of: deck.id, in: decks)).tag(UUID?.some(deck.id))
                        }
                    }
                    .disabled(decks.isEmpty)
                    if decks.isEmpty || model.deckID == nil {
                        Text("Without a deck the block runs as a plain timer.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .tag:
                    TextField("Tag", text: $model.tag)
                }
            }

            Section("Ambience") {
                Toggle("Ambient sound while focusing", isOn: $model.ambienceEnabled)
                    .disabled(model.availableAmbienceTracks.isEmpty)
                if model.availableAmbienceTracks.isEmpty {
                    Text("No ambience loops are bundled with this build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Track", selection: $model.ambienceTrack) {
                        ForEach(model.availableAmbienceTracks, id: \.self) { Text($0.label).tag($0) }
                    }
                    .disabled(!model.ambienceEnabled)
                    Slider(value: $model.ambienceVolume, in: 0...1) { Text("Volume") }
                        .disabled(!model.ambienceEnabled)
                }
            }

            Section {
                Button("Start Focus") { Task { await model.start() } }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
    }

    private func minutes(
        _ title: String, value: Binding<Int>, range: ClosedRange<Int>
    ) -> some View {
        Stepper("\(title): \(value.wrappedValue) min", value: value, in: range)
    }

    // MARK: - Running

    private var running: some View {
        VStack(spacing: Theme.space5) {
            timer
            if model.isFocusing, let review = model.review {
                embeddedStudy(review)
            } else if model.isOnBreak {
                breakScreen
            } else if model.isPaused {
                Text("Session paused")
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer()
            }
            controls
        }
        .padding(Theme.space5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.studyBackdrop)
        .onChange(of: model.ambienceEnabled) { Task { await model.ambienceSettingsChanged() } }
        .onChange(of: model.ambienceTrack) { Task { await model.ambienceSettingsChanged() } }
        .onChange(of: model.ambienceVolume) { Task { await model.ambienceSettingsChanged() } }
    }

    private var timer: some View {
        VStack(spacing: Theme.space2) {
            Label(model.phaseTitle, systemImage: model.phaseSymbol)
                .font(.headline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.timerText)
                    // Deliberately fixed at 72pt: this is the one glanceable element of
                    // the running screen and it must not reflow every second.
                    .font(.system(size: 72, weight: .light, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .accessibilityLabel("\(model.phaseTitle), \(model.timerText)")
                if model.isOpenEnded {
                    Text("∞")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.tertiary)
                        .help("Open-ended block — the timer counts up")
                        .accessibilityLabel("Open-ended block, the timer counts up")
                }
            }
            if let progress = model.goalProgress {
                VStack(spacing: Theme.space1) {
                    ProgressView(value: progress).tint(Theme.accent)
                    if let detail = model.goalDetail {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: 380)
            }
            if model.goalReached {
                Label("Goal reached", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func embeddedStudy(_ review: ReviewSessionViewModel) -> some View {
        Group {
            if review.isLoading {
                ProgressView().frame(maxHeight: .infinity)
            } else if let item = review.item {
                // Elevation comes from `StudyCardView.cardSurface()`.
                StudyCardView(model: review, item: item) {
                    Task { await model.recordCardGraded() }
                }
                .frame(maxWidth: 640)
            } else {
                ContentUnavailableView(
                    "Queue empty",
                    systemImage: "checkmark.circle",
                    description: Text("Nothing left to review here — keep focusing or stop the session.")
                )
                .frame(maxHeight: .infinity)
            }
        }
        .task { await review.start() }
    }

    private var breakScreen: some View {
        VStack(spacing: Theme.space3) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Look away from the screen. Stretch. Breathe.")
                .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    private var controls: some View {
        HStack(spacing: Theme.space3) {
            if model.isPaused {
                Button("Resume") { Task { await model.resume() } }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Pause") { Task { await model.pause() } }
            }
            Button("Stop", role: .destructive) { Task { await model.stop() } }
        }
        .controlSize(.large)
    }

    // MARK: - Completion

    private var completion: some View {
        ContentUnavailableView {
            Label(
                model.goalReached ? "Goal reached" : "Session complete",
                systemImage: model.goalReached ? "checkmark.seal.fill" : "checkmark.circle"
            )
        } description: {
            Text(model.sessionSummary)
        } actions: {
            Button("Done") { model.dismissSummary() }
                .keyboardShortcut(.defaultAction)
        }
    }
}
