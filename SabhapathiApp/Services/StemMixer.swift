import Foundation
import Combine

/// Manages per-stem volume and mute states, including chorus vocal mixback.
final class StemMixer: ObservableObject {
    @Published var volumes: [String: Float] = [
        "vocals": 0.0,   // Muted by default (karaoke mode)
        "drums": 1.0,
        "bass": 1.0,
        "other": 1.0,
    ]

    @Published var muted: [String: Bool] = [
        "vocals": true,
        "drums": false,
        "bass": false,
        "other": false,
    ]

    @Published var chorusVocalVolume: Float = 0.4  // -6dB roughly

    private let audioEngine: AudioEngineService

    init(audioEngine: AudioEngineService = .shared) {
        self.audioEngine = audioEngine
    }

    func setVolume(stem: String, volume: Float) {
        volumes[stem] = volume
        if !muted[stem, default: false] {
            audioEngine.setVolume(for: stem, volume: volume)
        }
    }

    func toggleMute(stem: String) {
        let isMuted = muted[stem, default: false]
        muted[stem] = !isMuted
        if !isMuted {
            audioEngine.setVolume(for: stem, volume: 0.0)
        } else {
            audioEngine.setVolume(for: stem, volume: volumes[stem, default: 1.0])
        }
    }

    /// Apply chorus mode: mix vocals back at reduced volume during chorus sections.
    func applyChorusMode(
        currentTime: TimeInterval,
        chorusSections: [ChorusSection]
    ) {
        let inChorus = chorusSections.contains {
            currentTime >= $0.startTime && currentTime <= $0.endTime
        }

        if inChorus {
            audioEngine.setVolume(for: "vocals", volume: chorusVocalVolume)
        } else if muted["vocals", default: true] {
            audioEngine.setVolume(for: "vocals", volume: 0.0)
        }
    }

    func resetToKaraoke() {
        volumes["vocals"] = 0.0
        muted["vocals"] = true
        audioEngine.setVolume(for: "vocals", volume: 0.0)

        for stem in ["drums", "bass", "other"] {
            volumes[stem] = 1.0
            muted[stem] = false
            audioEngine.setVolume(for: stem, volume: 1.0)
        }
    }

    func resetToOriginal() {
        for stem in ["vocals", "drums", "bass", "other"] {
            volumes[stem] = 1.0
            muted[stem] = false
            audioEngine.setVolume(for: stem, volume: 1.0)
        }
    }
}
