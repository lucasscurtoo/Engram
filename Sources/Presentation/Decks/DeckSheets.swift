import Domain
import SwiftUI

/// Create a deck (name + optional parent) or rename one. Same form, two titles.
struct DeckFormSheet: View {
    let title: String
    let decks: [Deck]
    let showsParentPicker: Bool
    let save: (String, UUID?) async -> Void

    @State private var name: String
    @State private var parentID: UUID?
    @Environment(\.dismiss) private var dismiss

    init(
        title: String, decks: [Deck], name: String, parentID: UUID?,
        showsParentPicker: Bool, save: @escaping (String, UUID?) async -> Void
    ) {
        self.title = title
        self.decks = decks
        self.showsParentPicker = showsParentPicker
        self.save = save
        _name = State(initialValue: name)
        _parentID = State(initialValue: parentID)
    }

    var body: some View {
        SheetLayout(title: title, confirm: "Save", isConfirmEnabled: !trimmedName.isEmpty) {
            VStack(alignment: .leading, spacing: Theme.space4) {
                VStack(alignment: .leading, spacing: Theme.space2) {
                    SectionCaps("Name")
                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, Theme.space2)
                        .frame(minHeight: 26)
                        .raised()
                }
                if showsParentPicker {
                    VStack(alignment: .leading, spacing: Theme.space2) {
                        SectionCaps("Parent Deck")
                        Picker("Parent deck", selection: $parentID) {
                            Text("None (top level)").tag(UUID?.none)
                            ForEach(sortedDecks, id: \.id) { deck in
                                Text(DeckTree.fullName(of: deck.id, in: decks)).tag(UUID?.some(deck.id))
                            }
                        }
                        .labelsHidden()
                        .font(.callout)
                    }
                }
            }
            .padding(Theme.space4)
        } confirm: {
            let name = trimmedName
            let parentID = parentID
            Task { await save(name, parentID) }
        }
        .frame(minWidth: 400)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var sortedDecks: [Deck] {
        decks.sorted {
            DeckTree.fullName(of: $0.id, in: decks)
                .localizedStandardCompare(DeckTree.fullName(of: $1.id, in: decks)) == .orderedAscending
        }
    }
}

/// Per-deck FSRS knobs. Writes through `DeckService.updateConfig`.
struct DeckConfigSheet: View {
    let deckName: String
    let save: (DeckConfig) async -> Void

    @State private var config: DeckConfig

    init(deckName: String, config: DeckConfig, save: @escaping (DeckConfig) async -> Void) {
        self.deckName = deckName
        self.save = save
        _config = State(initialValue: config)
    }

    var body: some View {
        SheetLayout(title: deckName, confirm: "Save", isConfirmEnabled: true) {
            VStack(alignment: .leading, spacing: Theme.space3) {
                SectionCaps("Scheduling")
                VStack(alignment: .leading, spacing: Theme.space2) {
                    HStack {
                        Text("Desired retention")
                            .font(.callout)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(config.requestRetention.formatted(.percent.precision(.fractionLength(0))))
                            .font(Theme.mono(.callout))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Slider(value: $config.requestRetention, in: 0.7...0.97, step: 0.01)
                        .accessibilityLabel("Desired retention")
                }
                .padding(.horizontal, Theme.space3)
                .padding(.vertical, Theme.space2)
                .raised()

                counter("New cards per day", value: $config.newCardsPerDay, range: 0...500, step: 1)
                counter(
                    "Maximum reviews per day", value: $config.maxReviewsPerDay,
                    range: 0...9_999, step: 10
                )
            }
            .padding(Theme.space4)
        } confirm: {
            let config = config
            Task { await save(config) }
        }
        .frame(minWidth: 440)
    }

    private func counter(
        _ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack(spacing: Theme.space2) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: Theme.space2)
                Text("\(value.wrappedValue)")
                    .font(Theme.mono(.callout))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.horizontal, Theme.space3)
        .padding(.vertical, Theme.space2)
        .raised()
    }
}

/// Title + content + Cancel/Confirm footer. `confirm` runs, then the sheet closes.
/// Header and footer are hairline-separated bands on the content surface.
struct SheetLayout<Content: View>: View {
    let title: String
    let confirm: String
    let isConfirmEnabled: Bool
    @ViewBuilder let content: Content
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        title: String, confirm: String, isConfirmEnabled: Bool,
        @ViewBuilder content: () -> Content, confirm onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.confirm = confirm
        self.isConfirmEnabled = isConfirmEnabled
        self.content = content()
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.space4)
                .padding(.vertical, Theme.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .bottomHairline()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: Theme.space2) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.quiet)
                    .keyboardShortcut(.cancelAction)
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    HStack(spacing: Theme.space2) {
                        Text(confirm)
                        KeyHint("⏎", onAccent: true)
                    }
                }
                .buttonStyle(.accentAction)
                .keyboardShortcut(.defaultAction)
                .disabled(!isConfirmEnabled)
                .accessibilityLabel(confirm)
            }
            .padding(Theme.space4)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.hairline).frame(height: Theme.hairlineWidth)
            }
        }
        .background(Theme.bg1)
    }
}
