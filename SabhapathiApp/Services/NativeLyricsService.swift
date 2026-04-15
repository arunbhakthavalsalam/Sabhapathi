import Foundation
import os.log

/// V2: direct LRCLib lookup via URLSession, plus Whisper transcription via
/// subprocess to a small Python CLI shim. Replaces the FastAPI lyrics endpoints.
final class NativeLyricsService {
    private static let log = Logger(subsystem: "com.sabhapathi.karaoke", category: "Lyrics")

    enum LyricsError: Error, LocalizedError {
        case pythonMissing(String)
        case scriptMissing(String)
        case whisperFailed(String)
        case badRequest(String)

        var errorDescription: String? {
            switch self {
            case .pythonMissing(let p): return "Python interpreter not found at \(p)."
            case .scriptMissing(let p): return "Whisper script not found at \(p)."
            case .whisperFailed(let m): return "Whisper failed: \(m)"
            case .badRequest(let m): return "Lyrics request failed: \(m)"
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
    /// Returns nil (not throws) for "no match" — any transport-level failure
    /// is logged and also collapsed to nil so the caller can fall through to
    /// Whisper without needing to distinguish 404 from "couldn't connect".
    func searchLrcLib(title: String, artist: String, duration: TimeInterval?) async throws -> String? {
        guard var components = URLComponents(string: "https://lrclib.net/api/search") else {
            throw LyricsError.badRequest("could not build LRCLib URL")
        }
        var items: [URLQueryItem] = [URLQueryItem(name: "track_name", value: title)]
        if !artist.isEmpty { items.append(URLQueryItem(name: "artist_name", value: artist)) }
        if let duration, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        components.queryItems = items

        guard let url = components.url else {
            throw LyricsError.badRequest("invalid LRCLib query for title=\(title)")
        }

        var request = URLRequest(url: url)
        request.setValue("Sabhapathi Karaoke v2.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                Self.log.info("lrclib non-200 for '\(title, privacy: .public)'")
                return nil
            }
            let hits = try JSONDecoder().decode([LrcLibHit].self, from: data)
            return hits.compactMap(\.syncedLyrics).first { !$0.isEmpty }
        } catch {
            Self.log.info("lrclib error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
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

        // Drain both pipes concurrently via readability handlers so neither
        // can deadlock against a full kernel pipe buffer while Whisper is
        // still running (stderr in particular is chatty on long transcripts).
        let stdoutBox = LyricsDataBox()
        let stderrBox = LyricsDataBox()
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stdoutBox.append(data)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrBox.append(data)
        }

        Self.log.info("whisper start for \(projectId, privacy: .public)")

        do {
            try process.run()
        } catch {
            throw LyricsError.whisperFailed("could not launch: \(error.localizedDescription)")
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                if proc.terminationStatus == 0 {
                    let out = String(data: stdoutBox.value, encoding: .utf8) ?? ""
                    cont.resume(returning: out)
                } else {
                    let msg = String(data: stderrBox.value, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    Self.log.error("whisper exit \(proc.terminationStatus): \(msg, privacy: .public)")
                    cont.resume(throwing: LyricsError.whisperFailed(
                        msg.isEmpty ? "exit \(proc.terminationStatus)" : msg
                    ))
                }
            }
        }
    }
}

private final class LyricsDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = Data()
    var value: Data { lock.lock(); defer { lock.unlock() }; return _value }
    func append(_ d: Data) { lock.lock(); _value.append(d); lock.unlock() }
}
