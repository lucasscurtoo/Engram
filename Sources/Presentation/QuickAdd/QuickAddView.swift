import Domain
import SwiftUI

/// Capture-first window (Cmd+Shift+N): pick a deck, fill the note type's fields,
/// save, and the form clears itself for the next entry. Esc closes.
/// Writes through `DeckService.addNote`, exactly like the full editor.
struct QuickAddView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var decks: [Deck] = []
    @State private var noteTypes: [NoteType] = []
    @State private var selectedDeckID: UUID?
    @State private var selectedNoteTypeID: UUID?
    @State private var fields: [String: String] = [:]
    @State private var tagsText = ""
    @State private var savedCount = 0
    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            if !hasLoaded {
                // Otherwise the window opens claiming there are no decks.
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if decks.isEmpty {
                ContentUnavailableView(
                    "No decks yet — create one",
                    systemImage: "rectangle.stack",
                    description: Text("Add a deck in the main window first.")
                )
            } else {
                form
                footer
            }
        }
        .frame(minWidth: 420, minHeight: 420)
        .errorAlert(dependencies.errors)
        .task { await load() }
        .onExitCommand { dismiss() }
    }

    private var form: some View {
        Form {
            Picker("Deck", selection: $selectedDeckID) {
                ForEach(sortedDecks, id: \.id) { deck in
                    Text(DeckTree.fullName(of: deck.id, in: decks)).tag(UUID?.some(deck.id))
                }
            }
            if noteTypes.count > 1 {
                Picker("Note type", selection: $selectedNoteTypeID) {
                    ForEach(noteTypes, id: \.id) { type in
                        Text(type.name).tag(UUID?.some(type.id))
                    }
                }
            }
            if let noteType {
                NoteFieldsEditor(noteType: noteType, fields: $fields, tagsText: $tagsText)
            }
        }
        .formStyle(.grouped)
    }

    private var footer: some View {
        HStack {
            if savedCount > 0 {
                Text(savedCount == 1 ? "1 note added" : "\(savedCount) notes added")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding()
    }

    private var noteType: NoteType? {
        noteTypes.first { $0.id == selectedNoteTypeID }
    }

    private var sortedDecks: [Deck] {
        decks.sorted {
            DeckTree.fullName(of: $0.id, in: decks)
                .localizedStandardCompare(DeckTree.fullName(of: $1.id, in: decks)) == .orderedAscending
        }
    }

    private var canSave: Bool {
        selectedDeckID != nil && noteType != nil
            && fields.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func load() async {
        decks = await dependencies.errors
            .value({ try await dependencies.deckRepository.allDecks() }, fallback: [])
        noteTypes = await dependencies.availableNoteTypes()
        selectedDeckID = selectedDeckID ?? sortedDecks.first?.id
        selectedNoteTypeID = selectedNoteTypeID ?? noteTypes.first?.id
        hasLoaded = true
    }

    private func save() {
        guard let deckID = selectedDeckID, let noteType else { return }
        let fields = fields
        let tags = Tags.parse(tagsText)
        let service = dependencies.deckService
        let errors = dependencies.errors
        // Clear immediately so typing can continue while the write lands.
        self.fields = [:]
        tagsText = ""
        Task {
            var saved = false
            await errors.run {
                _ = try await service.addNote(
                    deckID: deckID, noteType: noteType, fields: fields, tags: tags, now: .now
                )
                saved = true
            }
            if saved { savedCount += 1 }
        }
    }
}

// TODO(owner): system-wide global hotkey (post-MVP)
