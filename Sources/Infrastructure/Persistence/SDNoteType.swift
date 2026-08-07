import Foundation
import SwiftData

/// Persistence mirror of `Domain.NoteType`. Field and template definitions are stored
/// as JSON blobs: they are Codable in Domain, never queried, and rewritten wholesale.
@Model
public final class SDNoteType {
    public var id: UUID = UUID()
    public var name: String = ""
    /// JSON-encoded `[FieldDef]`.
    public var fieldsData: Data = Data()
    /// JSON-encoded `[CardTemplate]`.
    public var templatesData: Data = Data()

    public init(id: UUID, name: String, fieldsData: Data, templatesData: Data) {
        self.id = id
        self.name = name
        self.fieldsData = fieldsData
        self.templatesData = templatesData
    }
}
