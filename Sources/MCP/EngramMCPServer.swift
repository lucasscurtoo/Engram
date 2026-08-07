import Foundation
import Domain
import Application
import Infrastructure
import SwiftData

/// Local MCP server (stdio transport, newline-delimited JSON-RPC 2.0) exposing the
/// Engram store to Claude Desktop / Claude Code. Deliberately LOCAL ONLY: the store
/// is personal data, and a remote server would need hosting + OAuth to be safe.
/// TODO(owner): remote access would be a Streamable HTTP transport behind real auth —
/// a second transport over this same tool table, not a rewrite.
struct EngramMCPServer {
    private let deckRepository: any DeckRepository
    private let noteRepository: any NoteRepository
    private let noteTypeRepository: any NoteTypeRepository
    private let deckService: DeckService
    private let statsService: StatsService

    init() throws {
        // ENGRAM_STORE_DIRECTORY overrides the store location (tests / experiments).
        let directory = ProcessInfo.processInfo.environment["ENGRAM_STORE_DIRECTORY"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let container = try ModelContainer.engram(directory: directory)
        let decks = SwiftDataDeckRepository(modelContainer: container)
        let cards = SwiftDataCardRepository(modelContainer: container)
        let notes = SwiftDataNoteRepository(modelContainer: container)
        deckRepository = decks
        noteRepository = notes
        noteTypeRepository = SwiftDataNoteTypeRepository(modelContainer: container)
        deckService = DeckService(
            deckRepository: decks, cardRepository: cards, noteRepository: notes,
            noteTypeRepository: SwiftDataNoteTypeRepository(modelContainer: container)
        )
        statsService = StatsService(
            reviewLogRepository: SwiftDataReviewLogRepository(modelContainer: container),
            cardRepository: cards,
            focusLogRepository: SwiftDataFocusSessionLogRepository(modelContainer: container)
        )
    }

    // MARK: - JSON-RPC dispatch

    /// Handles one message; returns the response object, or nil for notifications.
    func handle(_ message: [String: Any]) async -> [String: Any]? {
        let id = message["id"]
        guard let method = message["method"] as? String else {
            return errorResponse(id: id, code: -32600, message: "Invalid request")
        }
        // Notifications (no id) get no response.
        guard id != nil else { return nil }

        switch method {
        case "initialize":
            return response(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "engram", "version": "1.0.0"],
            ])
        case "ping":
            return response(id: id, result: [String: Any]())
        case "tools/list":
            return response(id: id, result: ["tools": Self.toolDefinitions])
        case "tools/call":
            let params = message["params"] as? [String: Any] ?? [:]
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let text = try await call(tool: name, arguments: arguments)
                return response(id: id, result: [
                    "content": [["type": "text", "text": text]]
                ])
            } catch {
                return response(id: id, result: [
                    "content": [["type": "text", "text": "Error: \(error.localizedDescription)"]],
                    "isError": true,
                ])
            }
        default:
            return errorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func response(id: Any?, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private func errorResponse(id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    // MARK: - Tools

    // Computed, not stored: [[String: Any]] is not Sendable, so a stored static
    // trips Swift 6 global-state checking. Built on demand, which is fine here.
    static var toolDefinitions: [[String: Any]] { [
        [
            "name": "list_decks",
            "description": "List every deck with its full path name, card count and cards due today.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
        [
            "name": "create_deck",
            "description": "Create a deck. Optionally nest it under a parent via its full path name (e.g. \"Math::Algebra\").",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Deck name (single segment, no ::)"],
                    "parent": ["type": "string", "description": "Full path of the parent deck, omit for top level"],
                ],
                "required": ["name"],
            ],
        ],
        [
            "name": "create_note",
            "description": "Add a study note (front/back, markdown supported) to a deck. Generates its review card automatically.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "deck": ["type": "string", "description": "Full path name of the target deck, e.g. \"Math::Fractions\""],
                    "front": ["type": "string", "description": "Question side (markdown)"],
                    "back": ["type": "string", "description": "Answer side (markdown)"],
                    "tags": ["type": "array", "items": ["type": "string"], "description": "Optional tags"],
                ],
                "required": ["deck", "front", "back"],
            ],
        ],
        [
            "name": "search_notes",
            "description": "Search notes by text and/or tag, optionally scoped to a deck (subdecks included).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Case-insensitive text to match in any field"],
                    "tag": ["type": "string"],
                    "deck": ["type": "string", "description": "Full path name of a deck to scope to"],
                    "limit": ["type": "integer", "description": "Max results, default 25"],
                ],
            ],
        ],
        [
            "name": "get_stats",
            "description": "Study statistics: reviews per day (30d), retention, cards by state, due counts and focus minutes.",
            "inputSchema": ["type": "object", "properties": [String: Any]()],
        ],
    ] }

    private func call(tool: String, arguments: [String: Any]) async throws -> String {
        switch tool {
        case "list_decks": try await listDecks()
        case "create_deck": try await createDeck(arguments)
        case "create_note": try await createNote(arguments)
        case "search_notes": try await searchNotes(arguments)
        case "get_stats": try await stats()
        default: throw MCPError("Unknown tool: \(tool)")
        }
    }

    private func listDecks() async throws -> String {
        let decks = try await deckRepository.allDecks()
        guard !decks.isEmpty else { return "No decks yet." }
        let summaries = try await deckService.summaries(now: Date())
        let lines = summaries
            .map { summary in
                let path = DeckTree.fullName(of: summary.deck.id, in: decks)
                let cards = summary.cardCount == 1 ? "1 card" : "\(summary.cardCount) cards"
                return "\(path) — \(cards), \(summary.dueCount) due today"
            }
            .sorted()
        return lines.joined(separator: "\n")
    }

    private func createDeck(_ args: [String: Any]) async throws -> String {
        guard let name = args["name"] as? String, !name.isEmpty else {
            throw MCPError("\"name\" is required")
        }
        var parentID: UUID?
        if let parentPath = args["parent"] as? String, !parentPath.isEmpty {
            parentID = try await resolveDeck(path: parentPath).id
        }
        let deck = try await deckService.createDeck(name: name, parentID: parentID, now: Date())
        let decks = try await deckRepository.allDecks()
        return "Created deck \"\(DeckTree.fullName(of: deck.id, in: decks))\"."
    }

    private func createNote(_ args: [String: Any]) async throws -> String {
        guard let deckPath = args["deck"] as? String,
              let front = args["front"] as? String,
              let back = args["back"] as? String else {
            throw MCPError("\"deck\", \"front\" and \"back\" are required")
        }
        let deck = try await resolveDeck(path: deckPath)
        let noteType = try await noteTypeRepository.noteType(id: NoteType.basic.id) ?? .basic
        let tags = (args["tags"] as? [Any])?.compactMap { $0 as? String } ?? []
        // Fields keyed by the note type's field defs — same seam the app editor uses.
        let note = try await deckService.addNote(
            deckID: deck.id, noteType: noteType,
            fields: ["front": front, "back": back], tags: tags, now: Date()
        )
        let tagInfo = note.tags.isEmpty ? "" : " [\(note.tags.map { "#\($0)" }.joined(separator: " "))]"
        return "Added note to \"\(deckPath)\"\(tagInfo). It is due for its first review now."
    }

    private func searchNotes(_ args: [String: Any]) async throws -> String {
        var deckIDs: [UUID]?
        if let deckPath = args["deck"] as? String, !deckPath.isEmpty {
            let deck = try await resolveDeck(path: deckPath)
            let all = try await deckRepository.allDecks()
            deckIDs = Array(DeckTree.subtreeIDs(of: deck.id, in: all))
        }
        let query = NoteQuery(
            deckIDs: deckIDs,
            text: (args["query"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            tag: (args["tag"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            limit: args["limit"] as? Int ?? 25
        )
        let notes = try await noteRepository.notes(matching: query)
        guard !notes.isEmpty else { return "No notes match." }
        let lines = notes.map { note in
            let front = note.fields["front"] ?? note.fields.values.first ?? ""
            let back = note.fields["back"] ?? ""
            let tags = note.tags.isEmpty ? "" : "  [\(note.tags.map { "#\($0)" }.joined(separator: " "))]"
            return "• \(front) → \(back)\(tags)"
        }
        return lines.joined(separator: "\n")
    }

    private func stats() async throws -> String {
        let overview = try await statsService.overview(now: Date())
        let reviews30 = overview.reviewsPerDay.reduce(0) { $0 + $1.count }
        let focus30 = overview.focusMinutesPerDay.reduce(0) { $0 + $1.count }
        let states = overview.cardsByState
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\(String(describing: $0.key)): \($0.value)" }
            .joined(separator: ", ")
        let retention = overview.retention.map { String(format: "%.0f%%", $0 * 100) } ?? "no data"
        return """
        Reviews last 30 days: \(reviews30)
        Retention (review-state cards): \(retention)
        Cards by state: \(states.isEmpty ? "none" : states)
        Due today: \(overview.dueToday) · next 7 days: \(overview.dueNextSevenDays)
        Focus: \(focus30) min in 30 days across \(overview.focusSessionsCompleted) sessions
        """
    }

    /// Case-insensitive full-path deck lookup; error message lists what exists.
    private func resolveDeck(path: String) async throws -> Deck {
        let decks = try await deckRepository.allDecks()
        if let match = decks.first(where: {
            DeckTree.fullName(of: $0.id, in: decks).lowercased() == path.lowercased()
        }) {
            return match
        }
        let available = decks
            .map { DeckTree.fullName(of: $0.id, in: decks) }
            .sorted()
            .joined(separator: ", ")
        throw MCPError(
            "No deck named \"\(path)\". Available: \(available.isEmpty ? "none — create one first" : available)"
        )
    }
}

struct MCPError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
