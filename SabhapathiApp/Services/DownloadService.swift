import Foundation

protocol DownloadService {
    func download(
        url: URL,
        projectId: String,
        onProgress: @Sendable @escaping (Double, String) -> Void
    ) async throws -> DownloadResult
}

struct DownloadResult {
    let title: String
    let outputPath: String
}

/// Live state for a YouTube download. Kept on ProjectManager so ProcessingView
/// can observe progress without polling a backend.
struct DownloadState: Equatable {
    enum Status: String { case downloading, completed, failed }

    var status: Status = .downloading
    var progress: Double = 0
    var message: String = "Starting..."
    var title: String?
    var outputPath: String?
}
