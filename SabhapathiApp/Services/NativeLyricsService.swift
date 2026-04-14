import Foundation

/// V2: direct LRCLib lookup via URLSession, plus Whisper transcription via
/// subprocess to a small Python CLI shim. Replaces the FastAPI lyrics endpoints.
final class NativeLyricsService {
    enum LyricsError: Error, LocalizedError {
        case pythonMissing(String)
        case scriptMissing(String)
        case whisperFailed(String)

        var errorDescription: String? {
            switch self {
            case .pythonMissing(let p): return "Python interpreter not found at \(p)."
            case .scriptMissing(let p): return "Whisper script not found at \(p)."
            case .whisperFailed(let m): return "Whisper failed: \(m)"
            }
        }
    }

    struct LrcLibHit: Decodable {
        let syncedLyrics: String?
    }

    private let pythonPath: String
    private let whisperScriptPath: String
    private let session: URLSession

    init(
        pythonPath: String = RuntimePaths.python,
        whisperScriptPath: String = RuntimePaths.whisperScript,
        session: URLSession = .shared
    ) {
        self.pythonPath = pythonPath
        self.whisperScriptPath = whisperScriptPath
        self.session = session
    }

    // MARK: - LRCLib

    /// Returns synced LRC content if LRCLib has a match, otherwise nil.
    func searchLrcLib(title: String, artist: String, duration: TimeInterval?) async throws -> String? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        var items: [URLQueryItem] = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty { items.append(URLQueryItem(name: "artist_name", value: artist)) }
        if let duration, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue("Sabhapathi Karaoke v2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return nil
        }
        let hits = try JSONDecoder().decode([LrcLibHit].self, from: data)
        return hits.compactMap(\.syncedLyrics).first { !$0.isEmpty }
    }

    // MARK: - Whisper subprocess

    func transcribeWhisper(audioPath: String, projectId: String) async throws -> String {
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            throw LyricsError.pythonMissing(pythonPath)
        }
        guard FileManager.default.fileExists(atPath: whisperScriptPath) else {
            throw LyricsError.scriptMissing(whisperScriptPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.environment = RuntimePaths.pythonProcessEnvironment()
        process.arguments = ["-u", whisperScriptPath, audioPath, projectId]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let out = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let err = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    cont.resume(returning: String(data: out, encoding: .utf8) ?? "")
                } else {
                    let msg = String(data: err, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    cont.resume(throwing: LyricsError.whisperFailed(
                        msg.isEmpty ? "exit \(process.terminationStatus)" : msg
                    ))
                }
            }
        }
    }
}
