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
            Form {
                TextField("Name", text: $name)
                if showsParentPicker {
                    Picker("Parent deck", selection: $parentID) {
                        Text("None (top level)").tag(UUID?.none)
                        ForEach(sortedDecks, id: \.id) { deck in
                            Text(DeckTree.fullName(of: deck.id, in: decks)).tag(UUID?.some(deck.id))
                        }
                    }
                }
            }
            .formStyle(.grouped)
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
            Form {
                Section("Scheduling") {
                    VStack(alignment: .leading) {
                        LabeledContent(
                            "Desired retention",
                            value: config.requestRetention.formatted(
                                .percent.precision(.fractionLength(0))
                            )
                        )
                        Slider(value: $config.requestRetention, in: 0.7...0.97, step: 0.01)
                    }
                    Stepper(
                        "New cards per day: \(config.newCardsPerDay)",
                        value: $config.newCardsPerDay, in: 0...500
                    )
                    Stepper(
                        "Maximum reviews per day: \(config.maxReviewsPerDay)",
                        value: $config.maxReviewsPerDay, in: 0...9999, step: 10
                    )
                }
            }
            .formStyle(.grouped)
        } confirm: {
            let config = config
            Task { await save(config) }
        }
        .frame(minWidth: 440)
    }
}

/// Title + content + Cancel/Confirm footer. `confirm` runs, then the sheet closes.
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
                .padding([.horizontal, .top])
            content
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirm) {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isConfirmEnabled)
            }
            .padding([.horizontal, .bottom])
        }
    }
}
