import Foundation
import AVFoundation
import os.log

/// Decodes an audio file and returns a downsampled array of peak magnitudes
/// (0...1) suitable for drawing a waveform. Work happens off the main actor;
/// callers `await` the result.
enum WaveformService {
    private static let log = Logger(subsystem: "com.sabhapathi.karaoke", category: "Waveform")

    /// Compute `binCount` peak magnitudes for the given audio file.
    /// Results are normalized so the loudest bin maps to 1.0.
    static func peaks(for url: URL, binCount: Int = 600) async -> [Float] {
        await Task.detached(priority: .userInitiated) {
            do {
                return try computePeaksSync(url: url, binCount: binCount)
            } catch {
                log.error("peaks(\(url.lastPathComponent, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }.value
    }

    private static func computePeaksSync(url: URL, binCount: Int) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let totalFrames = file.length
        guard totalFrames > 0, binCount > 0 else { return [] }

        let framesPerBin = max(AVAudioFrameCount(1),
                               AVAudioFrameCount(totalFrames / AVAudioFramePosition(binCount)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerBin) else {
            return []
        }

        var peaks: [Float] = []
        peaks.reserveCapacity(binCount + 1)

        var framesRead: AVAudioFramePosition = 0
        while framesRead < totalFrames {
            let remaining = AVAudioFrameCount(totalFrames - framesRead)
            let toRead = min(framesPerBin, remaining)
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: toRead)
            let frameLen = Int(buffer.frameLength)
            if frameLen == 0 { break }
            framesRead += AVAudioFramePosition(frameLen)

            var maxAbs: Float = 0
            if let channelData = buffer.floatChannelData {
                let channelCount = Int(format.channelCount)
                for ch in 0..<channelCount {
                    let samples = channelData[ch]
                    for i in 0..<frameLen {
                        let v = abs(samples[i])
                        if v > maxAbs { maxAbs = v }
                    }
                }
            }
            peaks.append(maxAbs)
        }

        let maxPeak = peaks.max() ?? 0
        if maxPeak > 0 {
            peaks = peaks.map { $0 / maxPeak }
        }
        return peaks
    }
}
