import Application
import AVFoundation
import Foundation

extension AmbienceTrack {
    /// Bundled loop asset name for this track.
    public var assetName: String { "ambience-\(rawValue)" }
}

/// Looping ambient sound for focus blocks, backed by `AVAudioPlayer` over assets
/// bundled as `ambience-rain` / `ambience-whiteNoise` / `ambience-cafe` (m4a or mp3).
///
/// No asset ships with the MVP: an unknown asset name is a silent no-op, and
/// `availableTracks()` lets the UI disable the options it cannot play.
///
/// TODO(owner): add ambience assets (2-3 royalty-free loops, m4a, added to the app target).
public actor AudioAmbienceController: AmbienceController {
    /// Tracks whose loop is actually bundled. The UI disables the rest.
    public static func availableTracks() -> [AmbienceTrack] {
        AmbienceTrack.allCases.filter { isAvailable($0.assetName) }
    }

    public func play(_ track: AmbienceTrack, volume: Double) {
        play(assetNamed: track.assetName, volume: volume)
    }

    private static let fileExtensions = ["m4a", "mp3"]

    private var player: AVAudioPlayer?
    private var currentAsset: String?

    public init() {}

    public nonisolated static func url(forAsset name: String) -> URL? {
        fileExtensions.lazy
            .compactMap { Bundle.main.url(forResource: name, withExtension: $0) }
            .first
    }

    public nonisolated static func isAvailable(_ name: String) -> Bool {
        url(forAsset: name) != nil
    }

    /// Starts (or switches to) the asset, looping forever. Missing asset → stops.
    public func play(assetNamed name: String, volume: Double) {
        guard let url = Self.url(forAsset: name) else { return stop() }
        if currentAsset != name || player == nil {
            player?.stop()
            player = try? AVAudioPlayer(contentsOf: url)
            player?.numberOfLoops = -1
            currentAsset = name
        }
        setVolume(volume)
        player?.play()
    }

    public func setVolume(_ volume: Double) {
        player?.volume = Float(min(1, max(0, volume)))
    }

    public func stop() {
        player?.stop()
        player = nil
        currentAsset = nil
    }
}
