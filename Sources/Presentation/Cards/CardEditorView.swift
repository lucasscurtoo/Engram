import Domain
import SwiftUI

/// Comma-separated tag text <-> `[String]`. Shared by the editor and Quick Add.
enum Tags {
    static func parse(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func format(_ tags: [String]) -> String {
        tags.joined(separator: ", ")
    }
}

/// One input per `FieldDef` of the note type — never a hardcoded front/back pair —
/// with a live preview through `FieldContentView`, plus tag editing.
/// Reused by `CardEditorView` and Quick Add.
///
/// Hand-built rather than a `Form`: grouped forms carry the stock macOS look this
/// design replaces. Sections are mini-caps, inputs are raised.
struct NoteFieldsEditor: View {
    let noteType: NoteType
    @Binding var fields: [String: String]
    @Binding var tagsText: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space4) {
            ForEach(noteType.fields, id: \.name) { def in
                VStack(alignment: .leading, spacing: Theme.space2) {
                    SectionCaps(def.name)
                    TextEditor(text: binding(for: def.name))
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(Theme.space2)
                        .frame(minHeight: 64)
                        .raised()
                    let content = fields[def.name] ?? ""
                    if !content.isEmpty {
                        HStack(alignment: .top, spacing: Theme.space2) {
                            Text("Preview").sectionCaps()
                            FieldContentView(def: def, content: content)
                                .font(.callout)
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: Theme.space2) {
                SectionCaps("Tags")
                // TODO(owner): real token field with completion once tags get heavy use.
                TextField("Comma separated", text: $tagsText)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Theme.space2)
                    .frame(minHeight: 26)
                    .raised()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(
            get: { fields[name] ?? "" },
            set: { fields[name] = $0 }
        )
    }
}

/// Note editor sheet. Create goes through `DeckService.addNote` (which generates the
/// cards); edit goes through `DeckService.updateNote`.
struct CardEditorView: View {
    enum Mode {
        case create(deckID: UUID)
        case edit(Note)
    }

    let mode: Mode
    let onSaved: () async -> Void

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    @State private var noteTypes: [NoteType] = []
    @State private var selectedNoteTypeID: UUID?
    @State private var fields: [String: String] = [:]
    @State private var tagsText = ""

    var body: some View {
        SheetLayout(title: title, confirm: "Save", isConfirmEnabled: canSave) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.space4) {
                    if noteTypes.count > 1, case .create = mode {
                        VStack(alignment: .leading, spacing: Theme.space2) {
                            SectionCaps("Note Type")
                            Picker("Note type", selection: $selectedNoteTypeID) {
                                ForEach(noteTypes, id: \.id) { type in
                                    Text(type.name).tag(UUID?.some(type.id))
                                }
                            }
                            .labelsHidden()
                            .font(.callout)
                        }
                    }
                    if let noteType {
                        NoteFieldsEditor(noteType: noteType, fields: $fields, tagsText: $tagsText)
                    } else {
                        Text("Loading note type…").foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(Theme.space4)
            }
        } confirm: {
            save()
        }
        // min, not fixed: at large Dynamic Type sizes the form has to be able to grow.
        .frame(minWidth: 520, minHeight: 460)
        .task { await load() }
    }

    private var title: String {
        switch mode {
        case .create: "New Note"
        case .edit: "Edit Note"
        }
    }

    private var noteType: NoteType? {
        noteTypes.first { $0.id == selectedNoteTypeID }
    }

    /// At least one field must carry content — an all-empty note generates useless cards.
    private var canSave: Bool {
        noteType != nil && fields.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func load() async {
        noteTypes = await dependencies.availableNoteTypes()
        switch mode {
        case .create:
            selectedNoteTypeID = selectedNoteTypeID ?? noteTypes.first?.id
        case .edit(let note):
            selectedNoteTypeID = note.noteTypeID
            fields = note.fields
            tagsText = Tags.format(note.tags)
        }
    }

    private func save() {
        guard let noteType else { return }
        let fields = fields
        let tags = Tags.parse(tagsText)
        let service = dependencies.deckService
        let errors = dependencies.errors
        let mode = mode
        // The sheet is already dismissing, so the alert belongs to the window behind it.
        Task {
            await errors.run {
                switch mode {
                case .create(let deckID):
                    _ = try await service.addNote(
                        deckID: deckID, noteType: noteType, fields: fields, tags: tags, now: .now
                    )
                case .edit(var note):
                    note.fields = fields
                    note.tags = tags
                    try await service.updateNote(note, now: .now)
                }
            }
            await onSaved()
        }
    }
}
