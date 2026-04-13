import Foundation

/// HTTP client for the FastAPI backend.
final class BackendAPIClient: ObservableObject {
    static let shared = BackendAPIClient()

    private var baseURL: URL {
        PythonBackendManager.shared.baseURL.appendingPathComponent("api")
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: - Separation

    struct SeparationRequest: Codable {
        let inputPath: String
        let projectId: String
        let model: String
    }

    struct SeparationResponse: Codable {
        let jobId: String
        let status: String
    }

    struct JobStatusResponse: Codable {
        let jobId: String
        let status: String
        let progress: Double
        let message: String
        let outputDir: String?
        let stems: [String: String]?
    }

    func startSeparation(inputPath: String, projectId: String, model: String = "htdemucs") async throws -> SeparationResponse {
        let url = baseURL.appendingPathComponent("separate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            SeparationRequest(inputPath: inputPath, projectId: projectId, model: model)
        )

        let (data, _) = try await URLSession.shared.data(for: request)
        return try decoder.decode(SeparationResponse.self, from: data)
    }

    func getJobStatus(jobId: String) async throws -> JobStatusResponse {
        let url = baseURL.appendingPathComponent("status").appendingPathComponent(jobId)
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode(JobStatusResponse.self, from: data)
    }

    // MARK: - Download

    struct DownloadRequest: Codable {
        let url: String
        let projectId: String
    }

    struct DownloadResponse: Codable {
        let jobId: String
        let status: String
    }

    struct DownloadStatusResponse: Codable {
        let jobId: String
        let status: String
        let progress: Double
        let message: String
        let title: String?
        let outputPath: String?
    }

    func startDownload(url: String, projectId: String) async throws -> DownloadResponse {
        let endpoint = baseURL.appendingPathComponent("download")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(DownloadRequest(url: url, projectId: projectId))

        let (data, _) = try await URLSession.shared.data(for: request)
        return try decoder.decode(DownloadResponse.self, from: data)
    }

    func getDownloadStatus(jobId: String) async throws -> DownloadStatusResponse {
        let url = baseURL.appendingPathComponent("download/status").appendingPathComponent(jobId)
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode(DownloadStatusResponse.self, from: data)
    }

    // MARK: - Lyrics

    struct LyricsSearchRequest: Codable {
        let title: String
        let artist: String
        let album: String
        let duration: Double?
    }

    struct LyricsResponse: Codable {
        let jobId: String?
        let status: String
        let source: String
        let lrcContent: String?
    }

    struct WhisperRequest: Codable {
        let audioPath: String
        let projectId: String
    }

    func searchLyrics(title: String, artist: String = "", album: String = "", duration: Double? = nil) async throws -> LyricsResponse {
        let url = baseURL.appendingPathComponent("lyrics/search")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            LyricsSearchRequest(title: title, artist: artist, album: album, duration: duration)
        )

        let (data, _) = try await URLSession.shared.data(for: request)
        return try decoder.decode(LyricsResponse.self, from: data)
    }

    func transcribeLyrics(audioPath: String, projectId: String) async throws -> LyricsResponse {
        let url = baseURL.appendingPathComponent("lyrics/transcribe")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            WhisperRequest(audioPath: audioPath, projectId: projectId)
        )

        let (data, _) = try await URLSession.shared.data(for: request)
        return try decoder.decode(LyricsResponse.self, from: data)
    }

    func getLyricsStatus(jobId: String) async throws -> LyricsResponse {
        let url = baseURL.appendingPathComponent("lyrics/status").appendingPathComponent(jobId)
        let (data, _) = try await URLSession.shared.data(from: url)
        return try decoder.decode(LyricsResponse.self, from: data)
    }
}
