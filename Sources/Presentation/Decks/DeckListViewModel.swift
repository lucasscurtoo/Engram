import Application
import Domain
import Foundation

/// One node of the sidebar tree, built from the flat `parentID` list.
struct DeckNode: Identifiable, Hashable {
    let summary: DeckService.DeckSummary
    /// `nil` for leaves so `OutlineGroup` draws no disclosure triangle.
    let children: [DeckNode]?

    var id: UUID { summary.deck.id }
}

/// Sidebar state over `DeckService`. Every mutation goes through the service and
/// then reloads the summaries — no local bookkeeping to drift out of sync.
@MainActor
@Observable
final class DeckListViewModel {
    private(set) var summaries: [DeckService.DeckSummary] = []
    private(set) var tree: [DeckNode] = []
    private(set) var isLoading = false

    private let deckService: DeckService
    private let errors: ErrorReporter

    init(deckService: DeckService, errors: ErrorReporter) {
        self.deckService = deckService
        self.errors = errors
    }

    var decks: [Deck] { summaries.map(\.deck) }

    func summary(for id: UUID) -> DeckService.DeckSummary? {
        summaries.first { $0.deck.id == id }
    }

    /// "Parent::Child" for pickers and detail headers.
    func fullName(of id: UUID) -> String {
        DeckTree.fullName(of: id, in: decks)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        await errors.run {
            summaries = try await deckService.summaries(now: .now)
            tree = Self.buildTree(summaries)
        }
    }

    func createDeck(name: String, parentID: UUID?) async {
        await perform { _ = try await self.deckService.createDeck(name: name, parentID: parentID, now: .now) }
    }

    func rename(deckID: UUID, to name: String) async {
        await perform { try await self.deckService.renameDeck(id: deckID, to: name) }
    }

    func delete(deckID: UUID) async {
        await perform { try await self.deckService.deleteDeck(id: deckID) }
    }

    func updateConfig(deckID: UUID, config: DeckConfig) async {
        await perform { try await self.deckService.updateConfig(deckID: deckID, config: config) }
    }

    private func perform(_ work: () async throws -> Void) async {
        await errors.run(work)
        await load()
    }

    /// Flat list -> tree. Cycle-safe (`visited`), and any deck the recursion never
    /// reaches — dangling parent, or a cycle — surfaces at the root instead of
    /// disappearing from the sidebar.
    private static func buildTree(_ summaries: [DeckService.DeckSummary]) -> [DeckNode] {
        let byParent = Dictionary(grouping: summaries) { $0.deck.parentID }
        var visited: Set<UUID> = []

        func node(_ summary: DeckService.DeckSummary) -> DeckNode? {
            guard visited.insert(summary.deck.id).inserted else { return nil }
            let children = nodes(under: summary.deck.id)
            return DeckNode(summary: summary, children: children.isEmpty ? nil : children)
        }

        func nodes(under parentID: UUID?) -> [DeckNode] {
            (byParent[parentID] ?? []).sorted(by: byName).compactMap(node)
        }

        return nodes(under: nil) + summaries.sorted(by: byName).compactMap(node)
    }

    private static func byName(_ lhs: DeckService.DeckSummary, _ rhs: DeckService.DeckSummary) -> Bool {
        lhs.deck.name.localizedStandardCompare(rhs.deck.name) == .orderedAscending
    }
}
