import Domain
import SwiftUI

/// Note browser for a deck (subdecks included): text + tag filtering through
/// `NoteQuery`, edit and delete. Rows render the note type's *first* field —
/// there is no hardcoded "front".
///
/// Dense screen: 26pt raised fields, quiet buttons, ~30pt rows separated by hairlines.
struct CardListView: View {
    /// Deck new notes are filed into.
    let deckID: UUID
    /// `deckID` plus its subdecks — the browsing scope.
    let deckIDs: [UUID]
    /// Lets the sidebar refresh its counts after a write.
    let onNotesChanged: () async -> Void

    @Environment(AppDependencies.self) private var dependencies
    @Environment(StudyLauncher.self) private var launcher

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
            content
        }
        .background(Theme.bg1)
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
        HStack(spacing: Theme.space2) {
            FilterField(prompt: "Search notes", text: $searchText)
            FilterField(prompt: "Tag", text: $tagFilter).frame(width: 140)
            Button {
                launcher.scope = .tag(tagFilter)
            } label: {
                Label("Study Tag", systemImage: "play")
            }
            .buttonStyle(.quiet)
            .disabled(tagFilter.isEmpty)
            .help("Study every card tagged “\(tagFilter)”")
            Button {
                isAddingNote = true
            } label: {
                Label("New Note", systemImage: "plus")
            }
            .buttonStyle(.quiet)
            .help("New note in this deck")
            .accessibilityLabel("New note")
        }
        .padding(.horizontal, Theme.space4)
        .padding(.vertical, Theme.space2)
        .background(Theme.bg1)
        .bottomHairline()
    }

    @ViewBuilder
    private var content: some View {
        if !hasLoaded {
            // Without this the first frame claims "No notes yet" before the read lands.
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if notes.isEmpty {
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
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Theme.hairline)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editedNote = note }
                    .contextMenu {
                        Button("Edit…") { editedNote = note }
                        Divider()
                        Button("Delete…", role: .destructive) { notePendingDeletion = note }
                    }
                    .tag(note.id)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.bg1)
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
            // Not `uniqueKeysWithValues`: a store with two note types sharing an id
            // would trap. First one wins — the browser only needs a field to render.
            noteTypesByID = Dictionary(
                await dependencies.availableNoteTypes().map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        let query = NoteQuery(
            deckIDs: deckIDs,
            text: searchText.isEmpty ? nil : searchText,
            tag: tagFilter.isEmpty ? nil : tagFilter
        )
        notes = await dependencies.errors
            .value({ try await dependencies.noteRepository.notes(matching: query) }, fallback: [])
            .sorted { $0.modifiedAt > $1.modifiedAt }
        hasLoaded = true
    }

    private func reload() async {
        await load()
        await onNotesChanged()
    }

    private func delete(_ note: Note) {
        Task {
            await dependencies.errors.run {
                try await dependencies.noteRepository.delete(id: note.id)
            }
            await reload()
        }
    }
}

/// 26pt raised text field — the system's bezel is far too tall for this bar.
private struct FilterField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
            .font(.callout)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.space2)
            .frame(minHeight: 26)
            .raised()
    }
}

private struct NoteRow: View {
    let note: Note
    let noteType: NoteType?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.space3) {
            Group {
                if let def = noteType?.fields.first {
                    FieldContentView(def: def, content: note.fields[def.name] ?? "")
                } else {
                    Text("Unknown note type").foregroundStyle(Theme.textTertiary)
                }
            }
            .font(.callout)
            .lineLimit(1)
            Spacer(minLength: Theme.space3)
            if !note.tags.isEmpty {
                // Inline mono "#tag" instead of pills: a dense list cannot afford
                // four capsules per row.
                Text(note.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(Theme.mono(.subheadline))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.space4)
        .frame(minHeight: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovering ? Theme.bg2 : Color.clear)
        .onHover { isHovering = $0 }
    }
}
