import Foundation
import SwiftData

/// Persistence mirror of `Domain.NoteType`. Field and template definitions are stored
/// as JSON blobs: they are Codable in Domain, never queried, and rewritten wholesale.
@Model
public final class SDNoteType {
    public var id: UUID = UUID()
    public var name: String = ""
    /// `NoteTypeKind` raw value. Defaulted so pre-cloze stores migrate additively.
    public var kindRaw: String = "basic"
    /// JSON-encoded `[FieldDef]`.
    public var fieldsData: Data = Data()
    /// JSON-encoded `[CardTemplate]`.
    public var templatesData: Data = Data()

    public init(id: UUID, name: String, kindRaw: String, fieldsData: Data, templatesData: Data) {
        self.id = id
        self.name = name
        self.kindRaw = kindRaw
        self.fieldsData = fieldsData
        self.templatesData = templatesData
    }
}
