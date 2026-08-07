import Foundation

// TODO(owner): add ambience assets (2-3 royalty-free loops).
public enum AmbienceTrack: String, CaseIterable, Sendable, Codable {
    case rain
    case whiteNoise
    case cafe
}

/// Ambient sound during `focusing` blocks. Implementation lives in Infrastructure (M5).
public protocol AmbienceController: Sendable {
    func play(_ track: AmbienceTrack, volume: Double) async
    func setVolume(_ volume: Double) async
    func stop() async
}
