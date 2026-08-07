import Application
import Domain
import SwiftUI

/// Sidebar: hierarchical deck tree with rolled-up counts, plus the fixed
/// Stats/Focus entries.
///
/// Hand-rolled rather than `List(selection:)`: AppKit paints its own saturated
/// selection fill over any row background we supply, and its outline indent eats a
/// third of the column per level. Both are exactly the things this design has to
/// control, so the tree is a `ScrollView` of recursive rows with a 12pt indent step
/// and a 12% accent wash for selection. Rows stay 28pt with 1pt gaps — dense.
struct DeckListView: View {
    let model: DeckListViewModel
    @Binding var selection: AppRoute?

    @State private var sheet: DeckSheet?
    @State private var deckPendingDeletion: Deck?
    @State private var collapsed: Set<UUID> = []

    @Environment(StudyLauncher.self) private var launcher

    var body: some View {
        // A selection-less `List`: it still handles the titlebar safe area and the
        // sidebar's scroll chrome, but with no selection binding AppKit has nothing
        // to paint over the rows.
        List {
            // Traffic lights overlay this zone (hidden title bar) — keep it clear.
            Color.clear.frame(height: 26).sidebarRow()
            HStack(spacing: Theme.space2) {
                SectionCaps("Library")
                Spacer(minLength: 0)
                SidebarIconButton(symbol: "play.fill", help: "Study every deck") {
                    launcher.study(.all)
                }
                .accessibilityLabel("Study all decks")
                SidebarIconButton(symbol: "plus", help: "New deck") {
                    sheet = .add(parentID: nil)
                }
                .accessibilityLabel("New deck")
            }
            .padding(.horizontal, Theme.space2)
            .padding(.bottom, Theme.space1)
            .sidebarRow()
            if model.tree.isEmpty {
                Text(model.isLoading ? "Loading…" : "No decks yet")
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, Theme.space2)
                    .frame(minHeight: Self.rowHeight, alignment: .leading)
                    .sidebarRow()
            } else {
                ForEach(model.tree) { node in
                    DeckBranch(
                        node: node,
                        depth: 0,
                        selection: $selection,
                        collapsed: $collapsed,
                        menu: menu
                    )
                }
            }
            Color.clear.frame(height: Theme.space4).sidebarRow()
            SidebarRow(
                title: "Stats", symbol: "chart.bar.xaxis", isSelected: selection == .stats
            ) {
                selection = .stats
            }
            .sidebarRow()
            SidebarRow(
                title: "Focus", symbol: "timer", isSelected: selection == .focus
            ) {
                selection = .focus
            }
            .sidebarRow()
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, Self.rowHeight)
        .scrollContentBackground(.hidden)
        // Always reachable, never in the way.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NewDeckButton { sheet = .add(parentID: nil) }
        }
        .background(Theme.bg0.ignoresSafeArea())
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add(let parentID):
                DeckFormSheet(
                    title: "New Deck", decks: model.decks, name: "", parentID: parentID,
                    showsParentPicker: true
                ) { name, parentID in
                    await model.createDeck(name: name, parentID: parentID)
                }
            case .rename(let deck):
                DeckFormSheet(
                    title: "Rename Deck", decks: model.decks, name: deck.name,
                    parentID: deck.parentID, showsParentPicker: false
                ) { name, _ in
                    await model.rename(deckID: deck.id, to: name)
                }
            case .configure(let deck):
                DeckConfigSheet(deckName: model.fullName(of: deck.id), config: deck.config) { config in
                    await model.updateConfig(deckID: deck.id, config: config)
                }
            }
        }
        .confirmationDialog(
            deckPendingDeletion.map { "Delete “\($0.name)”?" } ?? "",
            isPresented: Binding(
                get: { deckPendingDeletion != nil },
                set: { if !$0 { deckPendingDeletion = nil } }
            ),
            presenting: deckPendingDeletion
        ) { deck in
            Button("Delete Deck", role: .destructive) {
                Task {
                    if selection == .deck(deck.id) { selection = nil }
                    await model.delete(deckID: deck.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its subdecks, notes and cards are deleted too. This cannot be undone.")
        }
    }

    /// Compact enough to read as a tool, tall enough to stay a comfortable hit target.
    static let rowHeight: CGFloat = 28
    /// One indent step. AppKit's own is more than twice this and swallows the column.
    static let indentStep: CGFloat = 12

    @ViewBuilder
    private func menu(for deck: Deck) -> some View {
        Button("Rename…") { sheet = .rename(deck) }
        Button("Add Subdeck…") { sheet = .add(parentID: deck.id) }
        Button("Configure…") { sheet = .configure(deck) }
        Divider()
        Button("Delete…", role: .destructive) { deckPendingDeletion = deck }
    }
}

/// Small quiet icon button for the sidebar header (Study All, New Deck).
private struct SidebarIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 22, height: 22)
                .background(isHovering ? Theme.bg3 : .clear, in: .rect(cornerRadius: Theme.Radius.control))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

private extension View {
    /// Strips every scrap of AppKit row chrome: no inset, no fill, no separator.
    func sidebarRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Theme.space1, bottom: 0, trailing: Theme.space1))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

private enum DeckSheet: Identifiable {
    case add(parentID: UUID?)
    case rename(Deck)
    case configure(Deck)

    var id: String {
        switch self {
        case .add(let parentID): "add-\(parentID?.uuidString ?? "root")"
        case .rename(let deck): "rename-\(deck.id)"
        case .configure(let deck): "configure-\(deck.id)"
        }
    }
}

/// One deck plus, when expanded, its subtree. Collapse state is tracked by id so a
/// reload of the tree never closes what the user opened.
private struct DeckBranch<Menu: View>: View {
    let node: DeckNode
    let depth: Int
    @Binding var selection: AppRoute?
    @Binding var collapsed: Set<UUID>
    @ViewBuilder let menu: (Deck) -> Menu

    var body: some View {
        DeckRow(
            summary: node.summary,
            depth: depth,
            isSelected: selection == .deck(node.id),
            disclosure: node.children == nil ? nil : !collapsed.contains(node.id),
            toggleDisclosure: {
                if collapsed.contains(node.id) {
                    collapsed.remove(node.id)
                } else {
                    collapsed.insert(node.id)
                }
            },
            select: { selection = .deck(node.id) }
        )
        .contextMenu { menu(node.summary.deck) }
        .sidebarRow()
        if let children = node.children, !collapsed.contains(node.id) {
            ForEach(children) { child in
                DeckBranch(
                    node: child, depth: depth + 1, selection: $selection,
                    collapsed: $collapsed, menu: menu
                )
            }
        }
    }
}

/// Selection is a 12% accent wash and nothing else — the label stays near-white so
/// contrast never depends on the accent. Hover is one layer of grey.
private struct SidebarRowBackground: View {
    let isSelected: Bool
    let isHovering: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.control)
            .fill(isSelected ? Theme.accentWash : (isHovering ? Theme.bg3 : .clear))
    }
}

/// Sidebar entry with the app's quiet icon treatment. Used by the fixed rows;
/// `DeckRow` mirrors its metrics so every row in the list lines up.
private struct SidebarRow: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.space2) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textTertiary)
                    .frame(width: 16)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.space2)
            .frame(minHeight: DeckListView.rowHeight)
            .background { SidebarRowBackground(isSelected: isSelected, isHovering: isHovering) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // Custom-drawn row: without this, VoiceOver reads an unnamed button.
        .accessibilityLabel(title)
    }
}

private struct DeckRow: View {
    let summary: DeckService.DeckSummary
    let depth: Int
    let isSelected: Bool
    /// nil for leaves; true/false = expanded/collapsed.
    let disclosure: Bool?
    let toggleDisclosure: () -> Void
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: Theme.space1) {
                chevron
                Text(summary.deck.name)
                    .font(.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Theme.space2)
                dueCount
            }
            .padding(.leading, Theme.space2 + CGFloat(depth) * DeckListView.indentStep)
            .padding(.trailing, Theme.space2)
            .frame(minHeight: DeckListView.rowHeight)
            .background { SidebarRowBackground(isSelected: isSelected, isHovering: isHovering) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // Custom-drawn row: without this, VoiceOver reads an unnamed button.
        .accessibilityLabel(
            summary.dueCount > 0
                ? "\(summary.deck.name), \(summary.dueCount) due today"
                : summary.deck.name
        )
    }

    @ViewBuilder
    private var chevron: some View {
        if let disclosure {
            Button(action: toggleDisclosure) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(disclosure ? 90 : 0))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(disclosure ? "Collapse \(summary.deck.name)" : "Expand \(summary.deck.name)")
        } else {
            Color.clear.frame(width: 12, height: 12)
        }
    }

    /// Plain accent mono digits while something is due, a quiet nothing once clear —
    /// a pill here would shout on every row of a dense list. `layoutPriority` keeps
    /// the number whole: the deck name is what may truncate.
    @ViewBuilder
    private var dueCount: some View {
        if summary.dueCount > 0 {
            Text("\(summary.dueCount)")
                .font(Theme.mono(.subheadline))
                .foregroundStyle(Theme.accent)
                .fixedSize()
                .layoutPriority(1)
                .help("Due today")
        }
    }
}

/// Ghost footer action: tertiary at rest, primary under the pointer.
private struct NewDeckButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label("New Deck", systemImage: "plus")
                .font(.callout)
                .foregroundStyle(isHovering ? Theme.textPrimary : Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.space3)
                .padding(.vertical, Theme.space2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .onHover { isHovering = $0 }
        // Opaque, or the last deck row scrolls underneath the footer.
        .background(Theme.bg0)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline).frame(height: Theme.hairlineWidth)
        }
    }
}
