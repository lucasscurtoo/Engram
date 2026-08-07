/// Seam 2: every note field declares how its raw string should be rendered.
/// Adding a content type means adding a renderer in Presentation — nothing else changes.
public enum ContentType: String, Sendable, Codable, Hashable {
    case markdown
    // TODO(owner): .latex, .code(language), .image — post-MVP, plug via ContentRenderer.
}
