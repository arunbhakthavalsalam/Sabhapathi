import Foundation

/// Orchestrates lyrics fetching: LRCLIB first, Whisper fallback.
final class LyricsService: ObservableObject {
    @Published var lyrics: [LyricsLine] = []
    @Published var isLoading = false
    @Published var source: String = ""

    private let api = BackendAPIClient.shared

    func fetchLyrics(for project: KaraokeProject) async -> [LyricsLine] {
        await MainActor.run { isLoading = true }

        // Try LRCLIB first
        do {
            let result = try await api.searchLyrics(
                title: project.song.title,
                artist: project.song.artist,
                duration: project.song.duration > 0 ? project.song.duration : nil
            )

            if result.status == "found", let lrc = result.lrcContent {
                let parsed = LRCParser.parse(lrc)
                await MainActor.run {
                    self.lyrics = parsed
                    self.source = "lrclib"
                    self.isLoading = false
                }
                return parsed
            }
        } catch {
            // Fall through to Whisper
        }

        // Whisper fallback: transcribe vocal stem
        if let vocalsPath = project.stemSet?.vocals?.path {
            do {
                let result = try await api.transcribeLyrics(
                    audioPath: vocalsPath,
                    projectId: project.id.uuidString
                )

                if let jobId = result.jobId {
                    let parsed = await pollWhisperJob(jobId: jobId)
                    await MainActor.run {
                        self.lyrics = parsed
                        self.source = "whisper"
                        self.isLoading = false
                    }
                    return parsed
                }
            } catch {
                // No lyrics available
            }
        }

        await MainActor.run { isLoading = false }
        return []
    }

    private func pollWhisperJob(jobId: String) async -> [LyricsLine] {
        for _ in 0..<120 {  // Max 2 minutes
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            do {
                let status = try await api.getLyricsStatus(jobId: jobId)
                if status.status == "completed", let lrc = status.lrcContent {
                    return LRCParser.parse(lrc)
                } else if status.status == "failed" {
                    return []
                }
            } catch {
                continue
            }
        }
        return []
    }
}
