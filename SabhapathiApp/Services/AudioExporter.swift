import Foundation
import AVFoundation
import os.log

/// Exports mixed audio to MP3 / WAV using the bundled ffmpeg binary.
final class AudioExporter {
    private static let log = Logger(subsystem: "com.sabhapathi.karaoke", category: "Exporter")

    enum ExportError: LocalizedError {
        case ffmpegNotFound
        case missingStems(String)
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound: return "ffmpeg binary not found"
            case .missingStems(let msg): return "Missing stems: \(msg)"
            case .exportFailed(let msg): return "Export failed: \(msg)"
            }
        }
    }

    enum Format: String, CaseIterable {
        case mp3
        case wav

        var fileExtension: String { rawValue }

        var ffmpegCodec: [String] {
            switch self {
            case .mp3: return ["-codec:a", "libmp3lame"]
            case .wav: return ["-codec:a", "pcm_s16le"]
            }
        }
    }

    /// Mix stems to a karaoke file (no vocals). Defaults to MP3 at 192 kbps.
    func exportKaraokeMP3(
        project: KaraokeProject,
        outputURL: URL,
        format: Format = .mp3,
        bitrateKbps: Int = 192
    ) throws {
        guard let karaoke = project.stemSet?.karaoke else {
            throw ExportError.missingStems("No karaoke stem available")
        }

        var args = ["-y", "-i", karaoke.path]
        args += format.ffmpegCodec
        if format == .mp3 { args += ["-b:a", "\(bitrateKbps)k"] }
        args += [outputURL.path]
        try runFFmpeg(args: args)
    }

    /// Export with chorus vocal mixback.
    func exportWithChorus(
        project: KaraokeProject,
        chorusSections: [ChorusSection],
        vocalVolume: Float,
        outputURL: URL,
        format: Format = .mp3,
        bitrateKbps: Int = 192
    ) throws {
        guard let stemSet = project.stemSet,
              let vocals = stemSet.vocals,
              let drums = stemSet.drums,
              let bass = stemSet.bass,
              let other = stemSet.other else {
            throw ExportError.missingStems("need vocals + drums + bass + other")
        }

        // Build ffmpeg filter for chorus sections
        var vocalFilter = "volume=0"
        if !chorusSections.isEmpty {
            let enables = chorusSections.map { section in
                "between(t,\(section.startTime),\(section.endTime))"
            }.joined(separator: "+")
            let db = 20 * log10(max(vocalVolume, 0.0001))
            vocalFilter = "volume=enable='\(enables)':volume=\(String(format: "%.1f", db))dB"
        }

        var args = [
            "-y",
            "-i", vocals.path,
            "-i", drums.path,
            "-i", bass.path,
            "-i", other.path,
            "-filter_complex",
            "[0:a]\(vocalFilter)[v];[1:a][2:a][3:a][v]amix=inputs=4:duration=longest",
        ]
        args += format.ffmpegCodec
        if format == .mp3 { args += ["-b:a", "\(bitrateKbps)k"] }
        args += [outputURL.path]
        try runFFmpeg(args: args)
    }

    /// Export LRC file alongside audio.
    func exportLRC(lyrics: [LyricsLine], to outputURL: URL) throws {
        let content = LRCParser.generate(from: lyrics)
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    // MARK: - ffmpeg runner

    /// Shared subprocess helper: streams stderr through a readability handler
    /// so ffmpeg can't deadlock on a saturated pipe while we block on exit,
    /// and surfaces the tail of stderr as the error message on non-zero exit.
    private func runFFmpeg(args: [String]) throws {
        let ffmpegPath = RuntimePaths.ffmpeg
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath) else {
            throw ExportError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        let stderrBox = ExporterDataBox()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrBox.append(data)
        }
        // Drain stdout too (ffmpeg rarely writes there in our pipeline, but
        // a full buffer would still deadlock).
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            throw ExportError.exportFailed("could not launch ffmpeg: \(error.localizedDescription)")
        }
        process.waitUntilExit()

        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutPipe.fileHandleForReading.readabilityHandler = nil

        if process.terminationStatus != 0 {
            let full = String(data: stderrBox.value, encoding: .utf8) ?? ""
            // ffmpeg is chatty — keep the last few lines, which carry the
            // actual error (codec missing, path bad, etc.).
            let tail = full
                .split(separator: "\n")
                .suffix(8)
                .joined(separator: "\n")
            Self.log.error("ffmpeg exit \(process.terminationStatus): \(tail, privacy: .public)")
            throw ExportError.exportFailed(tail.isEmpty
                ? "ffmpeg exited with code \(process.terminationStatus)"
                : tail)
        }
    }
}

private final class ExporterDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = Data()
    var value: Data { lock.lock(); defer { lock.unlock() }; return _value }
    func append(_ d: Data) { lock.lock(); _value.append(d); lock.unlock() }
}
