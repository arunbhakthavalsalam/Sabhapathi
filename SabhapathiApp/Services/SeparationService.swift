import Foundation

/// V2: protocol so ProcessingView can stay agnostic to backend vs native separation.
protocol SeparationService {
    func separate(
        inputPath: String,
        projectId: String,
        onProgress: @Sendable @escaping (Double, String) -> Void
    ) async throws -> SeparationResult
}

struct SeparationResult {
    let outputDir: String
    let stems: [String: String]
}

/// Live state for a separation run. Kept on ProjectManager so ProcessingView
/// can observe progress across navigation (same pattern as DownloadState).
struct SeparationState: Equatable {
    enum Status: String { case separating, completed, failed }

    var status: Status = .separating
    var progress: Double = 0
    var message: String = "Preparing..."
}
