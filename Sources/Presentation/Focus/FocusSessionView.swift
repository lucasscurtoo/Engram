import Application
import Domain
import SwiftUI

/// Focus mode, two states in one screen.
///
/// Setup is a hand-built control stack — `.formStyle(.grouped)` is the one piece of
/// stock macOS chrome this design cannot absorb, so sections are mini-caps headers
/// and every control sits on its own raised row. Running is deliberately bare: the
/// sidebar collapses (`ContentView`), the toolbar is gone, and all that is left is
/// the timer, the phase, the goal bar and — when the session carries a study scope —
/// the same card UI the review screen uses (`StudyCardView`).
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
        .background(Theme.bg0)
    }

    // MARK: - Setup

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space5) {
                section("Mode") {
                    Picker("Mode", selection: $model.modeKind) {
                        ForEach(FocusSessionViewModel.ModeKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if model.modeKind == .pomodoro {
                        HStack(spacing: Theme.space2) {
                            ForEach(FocusSessionViewModel.PomodoroPreset.all) { preset in
                                PresetChip(preset: preset, isActive: model.isActive(preset)) {
                                    model.apply(preset)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        minutes("Work", value: $model.workMinutes, range: 1...180)
                        minutes("Short break", value: $model.shortBreakMinutes, range: 1...60)
                        minutes("Long break", value: $model.longBreakMinutes, range: 1...90)
                        counter(
                            "Blocks before a long break",
                            value: $model.cyclesPerLongBreak, range: 1...12, unit: ""
                        )
                    } else {
                        row {
                            Toggle(isOn: $model.breakReminderEnabled) {
                                // The label must fill the row or the switch hugs it
                                // instead of sitting on the trailing edge.
                                Text("Remind me to take breaks")
                                    .font(.callout)
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .toggleStyle(.switch)
                        }
                        if model.breakReminderEnabled {
                            minutes("Every", value: $model.breakReminderMinutes, range: 5...240)
                        }
                    }
                }

                section("Goal") {
                    Picker("Goal", selection: $model.goalKind) {
                        ForEach(FocusSessionViewModel.GoalKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    switch model.goalKind {
                    case .none: EmptyView()
                    case .minutes: minutes("Focus for", value: $model.goalMinutes, range: 5...600)
                    case .cards:
                        counter("Review", value: $model.goalCards, range: 1...500, unit: "cards")
                    }
                }

                section("Study") {
                    Picker("Study", selection: $model.attachmentKind) {
                        ForEach(FocusSessionViewModel.AttachmentKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    switch model.attachmentKind {
                    case .none:
                        EmptyView()
                    case .deck:
                        row {
                            Picker("Deck", selection: $model.deckID) {
                                Text("Select a deck").tag(UUID?.none)
                                ForEach(decks, id: \.id) { deck in
                                    Text(DeckTree.fullName(of: deck.id, in: decks)).tag(UUID?.some(deck.id))
                                }
                            }
                            .disabled(decks.isEmpty)
                            .font(.callout)
                        }
                        if decks.isEmpty || model.deckID == nil {
                            hint("Without a deck the block runs as a plain timer.")
                        }
                    case .tag:
                        row {
                            TextField("Tag", text: $model.tag)
                                .textFieldStyle(.plain)
                                .font(.callout)
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                }

                section("Ambience") {
                    row {
                        Toggle(isOn: $model.ambienceEnabled) {
                            Text("Ambient sound while focusing")
                                .font(.callout)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(.switch)
                        .disabled(model.availableAmbienceTracks.isEmpty)
                    }
                    if model.availableAmbienceTracks.isEmpty {
                        hint("No ambience loops are bundled with this build.")
                    } else {
                        row {
                            Picker("Track", selection: $model.ambienceTrack) {
                                ForEach(model.availableAmbienceTracks, id: \.self) { Text($0.label).tag($0) }
                            }
                            .disabled(!model.ambienceEnabled)
                            .font(.callout)
                        }
                        row {
                            Slider(value: $model.ambienceVolume, in: 0...1) { Text("Volume") }
                                .disabled(!model.ambienceEnabled)
                        }
                    }
                }

                Button("Start Focus") { Task { await model.start() } }
                    .buttonStyle(AccentButtonStyle(verticalPadding: Theme.space2 + 2))
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, Theme.space2)
            }
            .padding(Theme.space5)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.space2) {
            SectionCaps(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every setup control lives on one of these — raised, hairlined, compact.
    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Theme.space3)
            .padding(.vertical, Theme.space2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .raised()
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
    }

    private func minutes(
        _ title: String, value: Binding<Int>, range: ClosedRange<Int>
    ) -> some View {
        counter(title, value: value, range: range, unit: "min")
    }

    /// Label left, monospaced value right, stepper on the trailing edge.
    private func counter(
        _ title: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String
    ) -> some View {
        row {
            Stepper(value: value, in: range) {
                HStack(spacing: Theme.space2) {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: Theme.space2)
                    Text(unit.isEmpty ? "\(value.wrappedValue)" : "\(value.wrappedValue) \(unit)")
                        .font(Theme.mono(.callout))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
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
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxHeight: .infinity)
            } else {
                Spacer()
            }
            controls
        }
        .padding(Theme.space5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg0)
        .onChange(of: model.ambienceEnabled) { Task { await model.ambienceSettingsChanged() } }
        .onChange(of: model.ambienceTrack) { Task { await model.ambienceSettingsChanged() } }
        .onChange(of: model.ambienceVolume) { Task { await model.ambienceSettingsChanged() } }
    }

    private var timer: some View {
        VStack(spacing: Theme.space3) {
            Label(model.phaseTitle, systemImage: model.phaseSymbol)
                .font(.subheadline.weight(.semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
            if let phaseProgress = model.phaseProgress {
                // Pomodoro: the ring from the app icon, with the countdown inside.
                ZStack {
                    Circle()
                        .stroke(Theme.hairline, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: phaseProgress)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: Theme.accentGlow, radius: 8)
                        .animation(reduceMotion ? nil : .linear(duration: 1), value: phaseProgress)
                    Text(model.timerText)
                        .font(Theme.mono(44, weight: .light))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
                .frame(width: 210, height: 210)
                .padding(Theme.space2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(model.phaseTitle), \(model.timerText)")
            } else {
                // Deep work: no phase to fill a ring with — the big count-up stays.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(model.timerText)
                        // Deliberately fixed at 72pt: this is the one glanceable element of
                        // the running screen and it must not reflow every second.
                        .font(Theme.mono(72, weight: .light))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .accessibilityLabel("\(model.phaseTitle), \(model.timerText)")
                    if model.isOpenEnded {
                        Text("∞")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(Theme.textTertiary)
                            .help("Open-ended block — the timer counts up")
                            .accessibilityLabel("Open-ended block, the timer counts up")
                    }
                }
            }
            if let dots = model.cycleDots {
                HStack(spacing: Theme.space2) {
                    ForEach(0..<dots.total, id: \.self) { index in
                        Circle()
                            .fill(index < dots.filled ? Theme.accent : Theme.bg3)
                            .frame(width: 8, height: 8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(dots.filled) of \(dots.total) blocks until the long break")
                .help("Blocks until the long break")
            }
            if let progress = model.goalProgress {
                VStack(spacing: Theme.space2) {
                    ProgressView(value: progress).tint(Theme.accent)
                    if let detail = model.goalDetail {
                        Text(detail)
                            .font(Theme.mono(.subheadline))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: 380)
            }
            if model.goalReached {
                Label("Goal reached", systemImage: "checkmark.seal.fill")
                    .font(.callout)
                    .foregroundStyle(Theme.color(for: .easy))
            }
        }
    }

    private func embeddedStudy(_ review: ReviewSessionViewModel) -> some View {
        Group {
            if review.isLoading {
                ProgressView().frame(maxHeight: .infinity)
            } else if let item = review.item {
                // The surface comes from `StudyCardView.panel()`.
                StudyCardView(model: review, item: item) {
                    Task { await model.recordCardGraded() }
                }
                .frame(maxWidth: 640)
                .id(item.card.id)
                .transition(.opacity)
            } else {
                ContentUnavailableView(
                    "Queue empty",
                    systemImage: "checkmark.circle",
                    description: Text("Nothing left to review here — keep focusing or stop the session.")
                )
                .frame(maxHeight: .infinity)
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: Theme.quick), value: review.item?.card.id
        )
        .task { await review.start() }
    }

    /// Calm on purpose: nothing to look at is the point of a break.
    private var breakScreen: some View {
        Text("Look away from the screen. Stretch. Breathe.")
            .font(.callout)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxHeight: .infinity)
    }

    private var controls: some View {
        HStack(spacing: Theme.space3) {
            if model.isPaused {
                Button("Resume") { Task { await model.resume() } }
                    .buttonStyle(.accentAction)
            } else {
                Button("Pause") { Task { await model.pause() } }
                    .buttonStyle(.quiet)
            }
            Button("Stop", role: .destructive) { Task { await model.stop() } }
                .buttonStyle(QuietButtonStyle(tint: Theme.color(for: .again)))
        }
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
                .font(Theme.mono(.callout))
                .foregroundStyle(Theme.textSecondary)
        } actions: {
            Button("Done") { model.dismissSummary() }
                .buttonStyle(.accentAction)
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// One-tap pomodoro preset: bordered, compact, accent when it matches the current
/// numbers.
private struct PresetChip: View {
    let preset: FocusSessionViewModel.PomodoroPreset
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(preset.name) · \(preset.work)/\(preset.shortBreak)")
                .font(Theme.mono(.subheadline))
                .foregroundStyle(isActive ? Theme.accent : Theme.textSecondary)
                .padding(.horizontal, Theme.space2)
                .padding(.vertical, Theme.space1 + 1)
                .raised(
                    fill: isActive ? Theme.accent.opacity(0.10) : Theme.bg2,
                    border: isActive ? Theme.accent : Theme.hairline
                )
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(
            "\(preset.name) preset, \(preset.work) minute work, \(preset.shortBreak) minute break"
        )
    }
}
