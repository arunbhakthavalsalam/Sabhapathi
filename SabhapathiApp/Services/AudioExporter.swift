import Foundation
import AVFoundation

/// Exports mixed audio to MP3 using bundled ffmpeg.
final class AudioExporter {

    enum ExportError: LocalizedError {
        case ffmpegNotFound
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound: return "ffmpeg binary not found"
            case .exportFailed(let msg): return "Export failed: \(msg)"
            }
        }
    }

    /// Mix stems to a karaoke MP3 (no vocals).
    func exportKaraokeMP3(
        project: KaraokeProject,
        outputURL: URL
    ) throws {
        guard let karaoke = project.stemSet?.karaoke else {
            throw ExportError.exportFailed("No karaoke stem available")
        }

        let ffmpegPath = findFFmpeg()
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath) else {
            throw ExportError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-y", "-i", karaoke.path,
            "-codec:a", "libmp3lame", "-b:a", "192k",
            outputURL.path
        ]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ExportError.exportFailed(errorMessage)
        }
    }

    /// Export with chorus vocal mixback.
    func exportWithChorus(
        project: KaraokeProject,
        chorusSections: [ChorusSection],
        vocalVolume: Float,
        outputURL: URL
    ) throws {
        let ffmpegPath = findFFmpeg()
        guard FileManager.default.isExecutableFile(atPath: ffmpegPath) else {
            throw ExportError.ffmpegNotFound
        }

        guard let stemSet = project.stemSet,
              let vocals = stemSet.vocals,
              let drums = stemSet.drums,
              let bass = stemSet.bass,
              let other = stemSet.other else {
            throw ExportError.exportFailed("Missing stems")
        }

        // Build ffmpeg filter for chorus sections
        var vocalFilter = "volume=0"
        if !chorusSections.isEmpty {
            let enables = chorusSections.map { section in
                "between(t,\(section.startTime),\(section.endTime))"
            }.joined(separator: "+")
            let db = 20 * log10(vocalVolume)
            vocalFilter = "volume=enable='\(enables)':volume=\(String(format: "%.1f", db))dB"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-y",
            "-i", vocals.path,
            "-i", drums.path,
            "-i", bass.path,
            "-i", other.path,
            "-filter_complex",
            "[0:a]\(vocalFilter)[v];[1:a][2:a][3:a][v]amix=inputs=4:duration=longest",
            "-codec:a", "libmp3lame", "-b:a", "192k",
            outputURL.path
        ]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw ExportError.exportFailed("ffmpeg exited with code \(process.terminationStatus)")
        }
    }

    /// Export LRC file alongside audio.
    func exportLRC(lyrics: [LyricsLine], to outputURL: URL) throws {
        let content = LRCParser.generate(from: lyrics)
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
    }

    private func findFFmpeg() -> String {
        // Bundled ffmpeg in app resources
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("ffmpeg").path,
           FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        // Development: ffmpeg in project root
        let projectFFmpeg = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ffmpeg")
            .path
        if FileManager.default.isExecutableFile(atPath: projectFFmpeg) {
            return projectFFmpeg
        }
        // System fallback
        return "/opt/homebrew/bin/ffmpeg"
    }
}
