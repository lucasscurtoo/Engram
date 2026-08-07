import Domain
import SwiftUI

/// Note browser for a deck (subdecks included): text + tag filtering through
/// `NoteQuery`, edit and delete. Rows render the note type's *first* field —
/// there is no hardcoded "front".
struct CardListView: View {
    /// Deck new notes are filed into.
    let deckID: UUID
    /// `deckID` plus its subdecks — the browsing scope.
    let deckIDs: [UUID]
    /// Lets the sidebar refresh its counts after a write.
    let onNotesChanged: () async -> Void

    @Environment(AppDependencies.self) private var dependencies

    @State private var notes: [Note] = []
    @State private var noteTypesByID: [UUID: NoteType] = [:]
    @State private var searchText = ""
    @State private var tagFilter = ""
    @State private var selection: UUID?
    @State private var editedNote: Note?
    @State private var notePendingDeletion: Note?
    @State private var isAddingNote = false
    @State private var hasLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            filters
            Divider()
            content
        }
        .task(id: Query(deckIDs: deckIDs, text: searchText, tag: tagFilter)) {
            // Debounce typing; `.task(id:)` cancels the previous run for us.
            if hasLoaded {
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
            }
            await load()
        }
        .sheet(item: $editedNote) { note in
            CardEditorView(mode: .edit(note)) { await reload() }
        }
        .sheet(isPresented: $isAddingNote) {
            CardEditorView(mode: .create(deckID: deckID)) { await reload() }
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { notePendingDeletion != nil },
                set: { if !$0 { notePendingDeletion = nil } }
            ),
            presenting: notePendingDeletion
        ) { note in
            Button("Delete Note", role: .destructive) { delete(note) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its cards are deleted too. This cannot be undone.")
        }
    }

    private var filters: some View {
        HStack {
            TextField("Search notes", text: $searchText)
                .textFieldStyle(.roundedBorder)
            TextField("Tag", text: $tagFilter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
            Button {
                isAddingNote = true
            } label: {
                Label("New Note", systemImage: "plus")
            }
            .help("New note in this deck")
        }
        .padding(8)
    }

    @ViewBuilder
    private var content: some View {
        if notes.isEmpty {
            ContentUnavailableView(
                isFiltering ? "No notes match" : "No notes yet",
                systemImage: isFiltering ? "magnifyingglass" : "note.text",
                description: Text(
                    isFiltering
                        ? "Try a different search or tag."
                        : "Add one with the New Note button."
                )
            )
        } else {
            List(notes, selection: $selection) { note in
                NoteRow(note: note, noteType: noteTypesByID[note.noteTypeID])
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editedNote = note }
                    .contextMenu {
                        Button("Edit…") { editedNote = note }
                        Divider()
                        Button("Delete…", role: .destructive) { notePendingDeletion = note }
                    }
                    .tag(note.id)
            }
        }
    }

    private var isFiltering: Bool {
        !searchText.isEmpty || !tagFilter.isEmpty
    }

    /// Everything a reload depends on, in one `Hashable` so `.task(id:)` can watch it.
    private struct Query: Hashable {
        let deckIDs: [UUID]
        let text: String
        let tag: String
    }

    private func load() async {
        if noteTypesByID.isEmpty {
            noteTypesByID = Dictionary(
                uniqueKeysWithValues: await dependencies.availableNoteTypes().map { ($0.id, $0) }
            )
        }
        let query = NoteQuery(
            deckIDs: deckIDs,
            text: searchText.isEmpty ? nil : searchText,
            tag: tagFilter.isEmpty ? nil : tagFilter
        )
        notes = ((try? await dependencies.noteRepository.notes(matching: query)) ?? [])
            .sorted { $0.modifiedAt > $1.modifiedAt }
        hasLoaded = true
    }

    private func reload() async {
        await load()
        await onNotesChanged()
    }

    private func delete(_ note: Note) {
        Task {
            try? await dependencies.noteRepository.delete(id: note.id)
            await reload()
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let noteType: NoteType?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let def = noteType?.fields.first {
                FieldContentView(def: def, content: note.fields[def.name] ?? "")
                    .lineLimit(2)
            } else {
                Text("Unknown note type").foregroundStyle(.secondary)
            }
            if !note.tags.isEmpty {
                Text(note.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
