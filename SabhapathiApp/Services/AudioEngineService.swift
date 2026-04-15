import Foundation
import AVFoundation
import Combine
import os.log

/// Multi-stem audio playback using AVAudioEngine.
final class AudioEngineService: ObservableObject {
    static let shared = AudioEngineService()
    private static let log = Logger(subsystem: "com.sabhapathi.karaoke", category: "AudioEngine")

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private let engine = AVAudioEngine()
    private var playerNodes: [String: AVAudioPlayerNode] = [:]
    private var audioFiles: [String: AVAudioFile] = [:]
    private var mixerNodes: [String: AVAudioMixerNode] = [:]
    private var displayLink: Timer?

    /// Absolute offset (in seconds) of the last `scheduleSegment` start frame.
    /// Added to the running `playerTime.sampleTime` so `currentTime` stays
    /// accurate after seeking — without this, the seek bar snaps to 0.
    private var seekOffset: TimeInterval = 0

    let stemNames = ["vocals", "drums", "bass", "other"]

    func loadStems(from stemSet: StemSet) throws {
        stop()
        engine.reset()
        playerNodes.removeAll()
        audioFiles.removeAll()
        mixerNodes.removeAll()
        seekOffset = 0
        duration = 0
        currentTime = 0

        let mainMixer = engine.mainMixerNode

        let stemsToLoad: [(String, URL?)] = [
            ("vocals", stemSet.vocals),
            ("drums", stemSet.drums),
            ("bass", stemSet.bass),
            ("other", stemSet.other),
        ]

        do {
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

                if duration == 0 {
                    duration = Double(file.length) / file.processingFormat.sampleRate
                }
            }

            try engine.start()
        } catch {
            Self.log.error("loadStems failed: \(error.localizedDescription, privacy: .public)")
            // Roll back so the engine isn't left in a half-wired state on retry.
            engine.stop()
            engine.reset()
            playerNodes.removeAll()
            audioFiles.removeAll()
            mixerNodes.removeAll()
            duration = 0
            throw error
        }
    }

    func play() {
        for (name, player) in playerNodes {
            guard let file = audioFiles[name] else { continue }
            player.scheduleFile(file, at: nil)
            player.play()
        }
        seekOffset = 0
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
        seekOffset = 0
        stopTimeTracking()
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, duration))
        let wasPlaying = isPlaying

        for (name, player) in playerNodes {
            guard let file = audioFiles[name] else { continue }
            player.stop()

            let sampleRate = file.processingFormat.sampleRate
            let startFrame = AVAudioFramePosition(clamped * sampleRate)
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

        seekOffset = clamped
        currentTime = clamped
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
        stopTimeTracking()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateCurrentTime()
        }
        // .common keeps the timer firing while menus, sliders, or scroll views
        // are driving the main runloop — otherwise playback-position UI freezes.
        RunLoop.main.add(timer, forMode: .common)
        displayLink = timer
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
        let elapsed = Double(playerTime.sampleTime) / sampleRate
        let absolute = seekOffset + elapsed

        if absolute.isFinite && absolute >= 0 && absolute <= duration + 0.5 {
            currentTime = min(absolute, duration)
        }
    }
}
