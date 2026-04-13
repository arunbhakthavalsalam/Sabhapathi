import Foundation
import AVFoundation
import Combine

/// Multi-stem audio playback using AVAudioEngine.
final class AudioEngineService: ObservableObject {
    static let shared = AudioEngineService()

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private let engine = AVAudioEngine()
    private var playerNodes: [String: AVAudioPlayerNode] = [:]
    private var audioFiles: [String: AVAudioFile] = [:]
    private var mixerNodes: [String: AVAudioMixerNode] = [:]
    private var displayLink: Timer?

    let stemNames = ["vocals", "drums", "bass", "other"]

    func loadStems(from stemSet: StemSet) throws {
        stop()
        engine.reset()
        playerNodes.removeAll()
        audioFiles.removeAll()
        mixerNodes.removeAll()

        let mainMixer = engine.mainMixerNode

        let stemsToLoad: [(String, URL?)] = [
            ("vocals", stemSet.vocals),
            ("drums", stemSet.drums),
            ("bass", stemSet.bass),
            ("other", stemSet.other),
        ]

        for (name, url) in stemsToLoad {
            guard let url else { continue }

            let file = try AVAudioFile(forReading: url)
            let player = AVAudioPlayerNode()
            let mixer = AVAudioMixerNode()

            engine.attach(player)
            engine.attach(mixer)
            engine.connect(player, to: mixer, format: file.processingFormat)
            engine.connect(mixer, to: mainMixer, format: file.processingFormat)

            audioFiles[name] = file
            playerNodes[name] = player
            mixerNodes[name] = mixer

            // Set initial duration from first stem
            if duration == 0 {
                duration = Double(file.length) / file.processingFormat.sampleRate
            }
        }

        try engine.start()
    }

    func play() {
        for (name, player) in playerNodes {
            guard let file = audioFiles[name] else { continue }
            player.scheduleFile(file, at: nil)
            player.play()
        }
        isPlaying = true
        startTimeTracking()
    }

    func pause() {
        for player in playerNodes.values {
            player.pause()
        }
        isPlaying = false
        stopTimeTracking()
    }

    func stop() {
        for player in playerNodes.values {
            player.stop()
        }
        engine.stop()
        isPlaying = false
        currentTime = 0
        stopTimeTracking()
    }

    func seek(to time: TimeInterval) {
        let wasPlaying = isPlaying

        for (name, player) in playerNodes {
            guard let file = audioFiles[name] else { continue }
            player.stop()

            let sampleRate = file.processingFormat.sampleRate
            let startFrame = AVAudioFramePosition(time * sampleRate)
            let totalFrames = file.length
            guard startFrame < totalFrames else { continue }

            let remainingFrames = AVAudioFrameCount(totalFrames - startFrame)
            player.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: remainingFrames,
                at: nil
            )

            if wasPlaying {
                player.play()
            }
        }

        currentTime = time
    }

    func setVolume(for stem: String, volume: Float) {
        mixerNodes[stem]?.outputVolume = volume
    }

    func getVolume(for stem: String) -> Float {
        mixerNodes[stem]?.outputVolume ?? 1.0
    }

    func setMuted(for stem: String, muted: Bool) {
        mixerNodes[stem]?.outputVolume = muted ? 0.0 : 1.0
    }

    private func startTimeTracking() {
        displayLink = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateCurrentTime()
        }
    }

    private func stopTimeTracking() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func updateCurrentTime() {
        guard let (name, player) = playerNodes.first(where: { $0.value.isPlaying }),
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return }

        let sampleRate = audioFiles[name]?.processingFormat.sampleRate ?? 44100
        currentTime = Double(playerTime.sampleTime) / sampleRate
    }
}
