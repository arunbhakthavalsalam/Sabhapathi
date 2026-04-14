import Foundation

/// V2 prototype: invokes the bundled yt-dlp_macos binary directly from Swift.
/// Replaces the FastAPI `/api/download` endpoint for YouTube imports.
final class NativeDownloadService: DownloadService {
    enum DownloadError: Error, LocalizedError {
        case binaryMissing(String)
        case failed(String)
        case outputMissing

        var errorDescription: String? {
            switch self {
            case .binaryMissing(let path): return "yt-dlp binary not found at \(path)."
            case .failed(let msg): return msg
            case .outputMissing: return "yt-dlp finished but produced no audio file."
            }
        }
    }

    private let ytdlpPath: String
    private let ffmpegPath: String?
    private let projectsDir: URL

    init(
        ytdlpPath: String = RuntimePaths.ytdlp,
        ffmpegPath: String? = RuntimePaths.ffmpeg
    ) {
        self.ytdlpPath = ytdlpPath
        self.ffmpegPath = ffmpegPath
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.projectsDir = support
            .appendingPathComponent("Sabhapathi")
            .appendingPathComponent("projects")
    }

    func download(
        url: URL,
        projectId: String,
        onProgress: @Sendable @escaping (Double, String) -> Void
    ) async throws -> DownloadResult {
        guard FileManager.default.fileExists(atPath: ytdlpPath) else {
            throw DownloadError.binaryMissing(ytdlpPath)
        }

        let projectDir = projectsDir.appendingPathComponent(projectId)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let outputTemplate = projectDir.appendingPathComponent("original.%(ext)s").path

        var args: [String] = [
            "--no-playlist",
            "--format", "bestaudio/best",
            "--extract-audio",
            "--audio-format", "mp3",
            "--audio-quality", "192K",
            "--output", outputTemplate,
            "--newline",
            "--progress",
            "--no-warnings",
            "--print-json",
            "--no-simulate",
        ]
        if let ffmpegPath, FileManager.default.fileExists(atPath: ffmpegPath) {
            args += ["--ffmpeg-location", (ffmpegPath as NSString).deletingLastPathComponent]
        }
        args.append(url.absoluteString)

        onProgress(0.05, "Starting download...")
        let (title, stderr) = try await runYtDlp(args: args, onProgress: onProgress)

        let outputPath = try locateOutput(in: projectDir)
        if outputPath.isEmpty {
            let msg = stderr.isEmpty ? "" : stderr
            throw DownloadError.failed(msg.isEmpty ? "No audio file produced." : msg)
        }

        onProgress(1.0, "Downloaded.")
        return DownloadResult(title: title, outputPath: outputPath)
    }

    // MARK: - Subprocess

    private static let progressRegex = try! NSRegularExpression(
        pattern: #"^\[download\]\s+([0-9.]+)%"#
    )

    private func runYtDlp(
        args: [String],
        onProgress: @Sendable @escaping (Double, String) -> Void
    ) async throws -> (title: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let titleBox = TitleBox()
        let stdoutBuffer = StringBox()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

            let lines = stdoutBuffer.appendAndDrainLines(chunk)
            for line in lines {
                let ns = line as NSString
                if let m = Self.progressRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
                   m.numberOfRanges > 1,
                   let pct = Double(ns.substring(with: m.range(at: 1))) {
                    let scaled = 0.1 + (pct / 100.0) * 0.75
                    onProgress(scaled, "Downloading: \(Int(pct))%")
                    continue
                }
                if line.contains("[ExtractAudio]") || line.contains("Destination:") {
                    onProgress(0.9, "Converting to MP3...")
                    continue
                }
                if line.hasPrefix("{"),
                   let data = line.data(using: .utf8),
                   let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let t = info["title"] as? String {
                    titleBox.set(t)
                }
            }
        }

        let stderrBuffer = DataBox()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrBuffer.append(data)
        }

        try process.run()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(String, String), Error>) in
            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let stderr = String(data: stderrBuffer.value, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    cont.resume(returning: (titleBox.value ?? "Unknown", stderr))
                } else {
                    let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(throwing: DownloadError.failed(
                        msg.isEmpty ? "yt-dlp exited with code \(proc.terminationStatus)" : msg
                    ))
                }
            }
        }
    }

    private func locateOutput(in projectDir: URL) throws -> String {
        let primary = projectDir.appendingPathComponent("original.mp3")
        if FileManager.default.fileExists(atPath: primary.path) {
            return primary.path
        }
        for ext in ["m4a", "wav", "opus", "webm"] {
            let candidate = projectDir.appendingPathComponent("original.\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        throw DownloadError.outputMissing
    }
}

/// Small mutable box to capture the parsed title from the stdout handler closure.
private final class TitleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?
    var value: String? { lock.lock(); defer { lock.unlock() }; return _value }
    func set(_ v: String) { lock.lock(); _value = v; lock.unlock() }
}

/// Line-buffered stdout accumulator. Returns fully-terminated lines on each append.
private final class StringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var remainder = ""
    func appendAndDrainLines(_ chunk: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        remainder += chunk
        var lines = remainder.components(separatedBy: "\n")
        remainder = lines.removeLast()
        return lines
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = Data()
    var value: Data { lock.lock(); defer { lock.unlock() }; return _value }
    func append(_ d: Data) { lock.lock(); _value.append(d); lock.unlock() }
}
